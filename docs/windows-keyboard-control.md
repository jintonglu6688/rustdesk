# Windows keyboard control switching

`Ctrl+Shift+F11` switches between explicit local keyboard mode and remote input.
In local mode the connection, video and audio stay active. The remote canvas
leaves the focus order; focus goes to the existing keyboard menu, and the toolbar
stays visible. Hovering or clicking the canvas does not cancel local mode.
Use Alt+Tab to switch local applications. Press the same shortcut in any local
application to return to the last session explicitly switched to local mode.
Windows restores its window, the page selects its tab, and remote input resumes
after the whole chord is released. The target is the most recently suspended
session, not whichever other remote tab happens to be selected.

The keyboard menu exposes the mode and shortcut in its accessible name and
offers a normal menu action for switching. Its shortcut submenu selects
Ctrl+Shift with F8, F9, F10 or F11; the preference is local to this computer.
Each switch also uses Flutter's existing accessibility announcement channel.

Only a selected, foreground, connected desktop session can resume input.
Covered dialogs, view-only sessions and missing keyboard permission block
resuming. Releasing capture sends held key-up events to the peer and exits
relative mouse mode. Local mode is per session window and survives window
focus changes. Closing the session removes its native state. Global registration
exists only while there is a resumable local session; disconnecting, losing
keyboard permission or resuming releases it. A registration conflict displays an
error in the session; the existing menu and foreground shortcut remain usable.

The exit path uses the existing rdev hook. The return path uses Win32
`RegisterHotKey` with `MOD_NOREPEAT`, on a dedicated message thread. This follows
[Windows foreground activation rules](https://devblogs.microsoft.com/oldnewthing/20090226-00/?p=19013/).
A 30 ms timer runs only while a resume target exists, to check connection
eligibility, shortcut changes and complete chord release. It never records
ordinary typing. Activation occurs in `WM_HOTKEY`; Flutter then rechecks window,
tab, dialog and permission guards before enabling input.

## Regression surface

- `src/platform/windows_keyboard_control.rs` contains Windows-only ownership
  and shortcut handling. `src/keyboard.rs` calls it before rdev forwarding and
  rejects automatic grabs for explicitly local sessions.
- `src/flutter_ffi.rs` provides synchronous ownership operations and clears
  state on close. Generated bridges are rebuilt with the existing FRB tool.
  `flutter/lib/web/bridge.dart` supplies unsupported-platform stubs.
- `flutter/lib/models/windows_keyboard_control.dart` handles Flutter-source
  shortcuts and local-mode state. `input_model.dart` gates physical forwarding
  and automatic entry; `model.dart` routes the native notification and disposal.
- `flutter/lib/desktop/pages/remote_page.dart` owns foreground/tab/dialog guards,
  focus transfer, canvas focus exclusion and announcements. These hooks are
  necessary to select the saved destination tab and prevent a global shortcut
  from restoring remote input through a local dialog.
- `flutter/lib/desktop/widgets/remote_toolbar.dart` keeps the existing keyboard
  menu reachable in local mode and adds switching/shortcut commands. Existing
  menu buttons only gain an optional focus node.
- `src/lang/*.rs` append the five labels (Chinese translations; other missing
  translations fall back to English). Existing translations are preserved.

No server protocol, remote permissions, audio path, Flutter engine patch or
Android keyboard behavior changes. Existing Windows automatic capture remains
in use until the user explicitly switches to local mode.

## Validation

- Five Flutter tests cover global activation before input, failed activation or
  page checks, repeat suppression, full chord release, blocked/inactive pages and
  changing the shortcut. These do not simulate Windows hotkey delivery.
- The existing CM/mnemonic/tab/hidden-focus/modifier tests plus these tests pass:
  52 tests in total.
- Targeted Flutter analysis reports no errors or warnings; 12 existing info
  diagnostics remain. Rust Release build with `flutter,hwcodec` and the production
  Windows Flutter Release build pass.
- The generated installer is in
  `E:\rustdesk\dist\rustdesk-1.5.0-jtl-keyboard-global-fix-x86_64-install.exe`.
  All 107 payload files are compared after decompression against the candidate
  directory. The Rust core, AOT and paired accessibility engine are checked.
- Computer Use launched the candidate and read the real home accessibility tree;
  the connection input, buttons and existing mnemonics remain exposed. Automated
  connection setup then failed with `CUA_EXECUTION_FAILED`; refreshing the window
  list returned `CUA_TURN_NOT_ACTIVE`. This automation did not verify global
  activation or remote routing.
- On 2026-10-18 the user confirmed the corrected build passed the Windows
  host-to-VM test: switch to local control, then use the global shortcut to
  activate the session and resume remote control.
- The broader matrix of NVDA/ZDSR/BoyPcReader hook ordering, speech announcements,
  held-modifier cleanup, both input sources and multiple remote windows remains
  unverified. Automated widget tests do not establish these results.
- In particular, test Windows configurations that use Ctrl+Shift to change
  input language: the remote may see the modifier prefix before the hook
  recognizes the reserved function key. This build uses the existing key
  release mechanism; it does not inject an unverified dummy key.

Live regression checklist: enter text remotely; switch local and use Tab and Alt+Tab;
press the shortcut from a different local application and verify the saved
session is activated and receives text again. Also verify that a manual Alt+Tab
back to the session keeps input local. Repeat with both input sources, a held/repeated shortcut,
an open local dialog, two sessions and each supported screen reader.

## Foreground activation without input resuming (2026-10-18)

The user's installed global-hotkey build did activate the window, but did not
resume input. Its log contains six `global resume requested` entries and no
`local=false` transition. The page then called `windowManager.isFocused()`.
The Windows remote engine deliberately does not register WindowManagerPlugin:
its `RustDeskRegisterPlugins` and the runner's window-created callback register
other plugins only. An isolated call with that channel absent reproduces
`MissingPluginException(No implementation found for method isFocused on channel window_manager)`.

The fix removes that call and uses the existing `desktop_multi_window` focus
events and page guards. It does not force the focus flags to true. Only the
existing global-resume callback in `remote_page.dart` changes; native hotkeys,
permissions, input forwarding and other window types keep their previous paths.

The earlier callback-based tests did not exercise real child-engine plugin
registration and therefore missed this failure. The isolated failing probe is
kept with diagnosis artifacts, not presented as an end-to-end regression test.
The 52 existing targeted tests pass after the fix. The user confirmed the live
local/remote switching test passed on 2026-10-18. Computer Use could not complete
the automated check: it failed with `CUA_EXECUTION_FAILED`, then
`CUA_TURN_NOT_ACTIVE`, during window observation.

Build logs, the failing API probe and package verification are under
`E:\codex\artifacts\rustdesk-keyboard-global-fix-2026-10-18`.
