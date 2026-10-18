//! Explicit local keyboard ownership for Windows Flutter session windows.
use super::{client, EventType, Key, KEYBOARD_HOOKED};
use crate::{common::GrabState, flutter, flutter_ffi::SessionID};
use std::{
    collections::HashSet,
    sync::{atomic::Ordering, Mutex},
};

pub const SHORTCUT_OPTION: &str = "local-keyboard-shortcut";

lazy_static::lazy_static! {
    static ref LOCAL_SESSIONS: Mutex<HashSet<u128>> = Mutex::new(HashSet::new());
    static ref CONSUMED_KEY: Mutex<Option<Key>> = Mutex::new(None);
    static ref RESUME_TARGET: Mutex<Option<ResumeTarget>> = Mutex::new(None);
    static ref HOTKEY_THREAD: u32 = start_hotkey_thread();
}

#[derive(Clone, Copy, PartialEq)]
struct ResumeTarget {
    id: SessionID,
    window: usize,
}

pub fn is_local(id: u128) -> bool {
    LOCAL_SESSIONS.lock().unwrap().contains(&id)
}

pub fn forget(id: SessionID) {
    LOCAL_SESSIONS.lock().unwrap().remove(&id.as_u128());
    let mut target = RESUME_TARGET.lock().unwrap();
    if target.as_ref().map(|t| t.id) == Some(id) {
        *target = None;
        drop(target);
        wake_hotkey_thread();
    }
}

fn is_foreground_process() -> bool {
    use winapi::um::winuser::{GetForegroundWindow, GetWindowThreadProcessId};
    let mut pid = 0;
    unsafe {
        GetWindowThreadProcessId(GetForegroundWindow(), &mut pid);
    }
    pid == std::process::id()
}

pub fn set_local(id: SessionID, local: bool) -> bool {
    let Some(session) = flutter::sessions::get_session_by_session_id(&id) else {
        return false;
    };
    if !session.is_default() {
        return false;
    }
    if !local
        && (!is_foreground_process()
            || !session
                .connection_round_state
                .lock()
                .unwrap()
                .is_connected()
            || !*session.server_keyboard_enabled.read().unwrap()
            || session.lc.read().unwrap().view_only.v)
    {
        return false;
    }
    if local {
        let newly_local = LOCAL_SESSIONS.lock().unwrap().insert(id.as_u128());
        if newly_local && is_foreground_process() {
            *RESUME_TARGET.lock().unwrap() = Some(ResumeTarget {
                id,
                window: unsafe { winapi::um::winuser::GetForegroundWindow() } as usize,
            });
            wake_hotkey_thread();
        }
        let mode = session.get_keyboard_mode();
        client::change_grab_status(GrabState::Wait, &mode, id.as_u128());
        // Flutter input does not own an rdev grab, but its keys use the same
        // release tracking. Always release to the original session.
        if flutter::get_cur_session_id() == id {
            for (key, mut event) in super::take_remote_keys() {
                event.event_type = EventType::KeyRelease(key);
                client::process_event_with_session(&mode, &event, None, &session);
            }
        }
    } else {
        forget(id);
        // The page acquires input only after its canvas has keyboard focus.
    }
    hbb_common::log::debug!("[keyboard-control] local={local}, session={id}");
    true
}

fn shortcut_key() -> Key {
    match crate::get_local_option(SHORTCUT_OPTION).as_str() {
        "F8" => Key::F8,
        "F9" => Key::F9,
        "F10" => Key::F10,
        _ => Key::F11,
    }
}

/// Release capture before forwarding the reserved key to the remote peer.
pub fn handle(key: Key, pressed: bool) -> bool {
    let mut consumed = CONSUMED_KEY.lock().unwrap();
    if *consumed == Some(key) {
        if !pressed {
            *consumed = None;
        }
        return true;
    }
    if !pressed
        || !KEYBOARD_HOOKED.load(Ordering::SeqCst)
        || !matches!(key, Key::F8 | Key::F9 | Key::F10 | Key::F11)
        || key != shortcut_key()
        || !is_foreground_process()
    {
        return false;
    }
    let modifiers = super::MODIFIERS_STATE.lock().unwrap();
    let down = |key| modifiers.get(&key).copied().unwrap_or(false);
    let matches = (down(Key::ControlLeft) || down(Key::ControlRight))
        && (down(Key::ShiftLeft) || down(Key::ShiftRight))
        && !down(Key::Alt)
        && !down(Key::AltGr)
        && !down(Key::MetaLeft)
        && !down(Key::MetaRight);
    drop(modifiers);
    if !matches {
        return false;
    }
    let id = flutter::get_cur_session_id();
    if !set_local(id, true) {
        return false;
    }
    *consumed = Some(key);
    if let Some(session) = flutter::sessions::get_session_by_session_id(&id) {
        session.push_event_to("keyboard_control_local", &[("local", "true")], &[&id]);
    }
    true
}

fn wake_hotkey_thread() {
    if *HOTKEY_THREAD == 0
        || unsafe {
            winapi::um::winuser::PostThreadMessageW(
                *HOTKEY_THREAD,
                winapi::um::winuser::WM_APP,
                0,
                0,
            )
        } == 0
    {
        hbb_common::log::error!(
            "Cannot update keyboard resume hotkey: {}",
            std::io::Error::last_os_error()
        );
    }
}

fn start_hotkey_thread() -> u32 {
    let (tx, rx) = std::sync::mpsc::sync_channel(1);
    if let Err(err) = std::thread::Builder::new()
        .name("keyboard-resume".into())
        .spawn(move || {
            use winapi::um::{processthreadsapi::GetCurrentThreadId, winuser::*};
            unsafe {
                let mut msg = std::mem::zeroed();
                PeekMessageW(&mut msg, std::ptr::null_mut(), 0, 0, PM_NOREMOVE);
                if tx.send(GetCurrentThreadId()).is_ok() {
                    resume_hotkey_loop();
                }
            }
        })
    {
        hbb_common::log::error!("Cannot start keyboard resume hotkey: {err}");
        return 0;
    }
    rx.recv().unwrap_or(0)
}

fn resumable(target: ResumeTarget) -> bool {
    let Some(session) = flutter::sessions::get_session_by_session_id(&target.id) else {
        return false;
    };
    let mut pid = 0;
    unsafe {
        winapi::um::winuser::GetWindowThreadProcessId(target.window as _, &mut pid);
    }
    pid == std::process::id()
        && is_local(target.id.as_u128())
        && session.is_default()
        && session
            .connection_round_state
            .lock()
            .unwrap()
            .is_connected()
        && *session.server_keyboard_enabled.read().unwrap()
        && !session.lc.read().unwrap().view_only.v
}

fn notify_resume(target: ResumeTarget, event: &str) {
    if let Some(session) = flutter::sessions::get_session_by_session_id(&target.id) {
        session.push_event_to::<&str>(event, &[], &[&target.id]);
    }
}

fn resume_hotkey_loop() {
    use winapi::um::winuser::*;
    // This thread owns its message queue and hotkey ID; no Flutter window
    // procedure or other DLL shares this registration.
    const HOTKEY_ID: i32 = 1;
    let mut registered = None;
    let mut attempted = None;
    let mut pending = None;
    let mut timer = 0;
    unsafe {
        let mut msg = std::mem::zeroed();
        while GetMessageW(&mut msg, std::ptr::null_mut(), 0, 0) > 0 {
            let mut target = *RESUME_TARGET.lock().unwrap();
            if let Some(t) = target {
                if !resumable(t) {
                    let mut stored = RESUME_TARGET.lock().unwrap();
                    if *stored == Some(t) {
                        *stored = None;
                    }
                    target = None;
                }
            }
            let key = match shortcut_key() {
                Key::F8 => VK_F8,
                Key::F9 => VK_F9,
                Key::F10 => VK_F10,
                _ => VK_F11,
            };
            let desired = target.map(|t| (t, key));
            // Do not turn the tail/repeat of the exit chord into a resume,
            // including when Flutter (input source 2) handled the first press.
            if desired != attempted && (desired.is_none() || chord_released(key)) {
                if registered.take().is_some() {
                    UnregisterHotKey(std::ptr::null_mut(), HOTKEY_ID);
                }
                pending = None;
                attempted = desired;
                if let Some((t, vk)) = desired {
                    if RegisterHotKey(
                        std::ptr::null_mut(),
                        HOTKEY_ID,
                        (MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT) as u32,
                        vk as u32,
                    ) != 0
                    {
                        registered = desired;
                        hbb_common::log::debug!(
                            "[keyboard-control] global resume registered, session={}",
                            t.id
                        );
                    } else {
                        hbb_common::log::warn!(
                            "Cannot register keyboard resume hotkey: {}",
                            std::io::Error::last_os_error()
                        );
                        notify_resume(t, "keyboard_control_hotkey_error");
                    }
                }
            }
            if target.is_some() && timer == 0 {
                // Also release registration on disconnect and notice a shortcut
                // preference changed by another session window.
                timer = SetTimer(std::ptr::null_mut(), 0, 30, None);
                if timer == 0 {
                    hbb_common::log::error!(
                        "Cannot start keyboard resume timer: {}",
                        std::io::Error::last_os_error()
                    );
                    break;
                }
            } else if target.is_none() && timer != 0 {
                KillTimer(std::ptr::null_mut(), timer);
                timer = 0;
            }
            if msg.message == WM_HOTKEY && msg.wParam == HOTKEY_ID as usize {
                if let Some((t, vk)) = registered {
                    if (msg.lParam >> 16) as i32 != vk {
                        continue;
                    }
                    // WM_HOTKEY grants foreground activation. An ordinary
                    // low-level hook callback does not have that guarantee.
                    let window = t.window as _;
                    if IsIconic(window) != 0 {
                        ShowWindowAsync(window, SW_RESTORE);
                    }
                    if SetForegroundWindow(window) != 0 || GetForegroundWindow() == window {
                        pending = Some((t, vk));
                        hbb_common::log::debug!(
                            "[keyboard-control] global resume requested, session={}",
                            t.id
                        );
                    } else {
                        hbb_common::log::warn!("Cannot activate keyboard resume window");
                    }
                }
            }
            if let Some((t, vk)) = pending {
                if chord_released(vk) {
                    pending = None;
                    if GetForegroundWindow() == t.window as _ && resumable(t) {
                        notify_resume(t, "keyboard_control_resume");
                    }
                }
            }
        }
        if registered.is_some() {
            UnregisterHotKey(std::ptr::null_mut(), HOTKEY_ID);
        }
        if timer != 0 {
            KillTimer(std::ptr::null_mut(), timer);
        }
    }
}

fn chord_released(key: i32) -> bool {
    use winapi::um::winuser::*;
    [key, VK_CONTROL, VK_SHIFT, VK_MENU, VK_LWIN, VK_RWIN]
        .iter()
        .all(|k| unsafe { GetAsyncKeyState(*k) >= 0 })
}
