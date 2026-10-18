# Windows accessibility patches

Use Flutter SDK 3.24.5 with Flutter engine 3.24.4 (`db49896cf25ceabc44096d5f088d86414e05a7aa`), matching RustDesk's Windows engine release build. Do not apply these changes to a newer SDK or reuse the old engine DLL.

`flutter-engine-3.24.4-accessibility.diff` adds a distinct `hasSelectedState` flag, only exposes Windows selection state when declared, keeps tooltip-only controls in the accessibility tree, and excludes ignored leaves from Windows accessibility hit testing. It also exposes indexed scroll collections with implicit scrolling and a positive item count as lists, preserving explicit control roles and leaving ordinary scroll containers and the default PageView as groups. It includes RustDesk's existing `ClearCurrent` and `hex_codec.h` build compatibility changes. Apply it to a clean engine checkout after syncing dependencies:

```powershell
git -C $engineSource apply E:\rustdesk\.github\patches\flutter-engine-3.24.4-accessibility.diff
git -C $engineSource apply E:\rustdesk\.github\patches\flutter-engine-3.24.4-cm-access-keys.diff
Set-Location (Split-Path $engineSource)
python .\flutter\tools\gn --runtime-mode=release --enable-unittests
ninja -C .\out\host_release flutter_windows flutter_windows_unittests
.\out\host_release\flutter_windows_unittests.exe --gtest_filter="AccessibilityBridgeWindows.*"
```

Apply `flutter-3.24.5-selection-state.diff` to the Flutter SDK root. The matching engine's `lib/ui/semantics.dart` and rebuilt platform kernel artifacts must also replace the SDK's cached UI declarations and patched SDK artifacts. Updating only the Dart source in `bin/cache/pkg/sky_engine` does not update the compiled platform kernel.

The paired patches also expose explicit `Semantics(tab: true)` and `Semantics(tabBar: true, verticalTabBar: ...)` annotations for the Windows settings navigation. They use bits 29-31 after the selected-state bit; bit 31 is represented as signed int32 in the native declarations. The Windows bridge maps these annotations to native Tab/TabItem roles, single-selection providers, orientation, and selection events. Tab items expose SelectionItem rather than Invoke. Other existing control roles and events retain their previous mappings. These annotations are specific to this patched SDK/Windows engine pair; they are not a claim of support in stock Flutter 3.24.5 or the web engine.

RustDesk's main page tabs use Left/Right and its setting categories use Up/Down, with Home/End and wrapping at either end. Only the selected item participates in Tab traversal; arrow keys select the page while focus stays in the tab control. Accessibility focus requests focus the item without selecting it. Main-page selection is applied immediately to prevent the old delayed page switch from putting Tab into the previous page. The separate Settings opener is hidden and excluded from focus when the Settings tab exists, and is restored when that tab is closed. The Windows main window's minimize/maximize/restore/close buttons retain their accessible actions and mouse behavior but leave Tab traversal; Alt+Space remains the keyboard entry point for those window operations. Remote-session windows retain their existing keyboard behavior.

```powershell
$sdk = 'D:\Dev\SDKs\Flutter-3.24.5\flutter'
$engineSource = 'D:\Dev\SDKs\rustdesk-engine\src\flutter'
$engineOut = Join-Path (Split-Path $engineSource) 'out'
$cache = Join-Path $sdk 'bin\cache\artifacts\engine'
git -C $sdk apply E:\rustdesk\.github\patches\flutter-3.24.5-selection-state.diff
Copy-Item "$engineSource\lib\ui\semantics.dart" "$sdk\bin\cache\pkg\sky_engine\lib\ui\semantics.dart"
Copy-Item "$engineOut\host_release\flutter_windows.dll" "$cache\windows-x64-release\flutter_windows.dll"
Copy-Item "$engineOut\host_release\flutter_windows.dll.lib" "$cache\windows-x64-release\flutter_windows.dll.lib"
Copy-Item "$engineOut\host_release\flutter_windows.dll.pdb" "$cache\windows-x64-release\flutter_windows.dll.pdb"
Copy-Item "$engineOut\host_release\gen_snapshot.exe" "$cache\windows-x64-release\gen_snapshot.exe"
Copy-Item "$engineOut\host_release\flutter_patched_sdk\*.dill" "$cache\common\flutter_patched_sdk_product"
python .\flutter\tools\gn --runtime-mode=debug --no-enable-unittests
ninja -C .\out\host_debug strong_platform
Copy-Item "$engineOut\host_debug\flutter_patched_sdk\*.dill" "$cache\common\flutter_patched_sdk"
```

On this machine, `D:\Dev\Env\rustdesk-engine.ps1` selects the existing VS 2019 toolchain because the engine's Clang 18 is incompatible with the installed VS 2022 STL headers. This toolchain needs its C++ ATL component (`Microsoft.VisualStudio.Component.VC.ATL`). The engine dependency `src/build/toolchain/win/setup_toolchain.py` uses the installed Windows SDK `10.0.26100.0` instead of its original `10.0.22621.0` pin. These are local build environment adjustments, separate from the accessibility patch.

Install the matching DLL and platform artifacts together before rebuilding RustDesk. Keep debug/test and release platform artifacts separate. These engine changes affect every control exposed through the Windows accessibility bridge; real selected/unselected states remain available. RustDesk's widget changes supply explicit button roles and category names, preventing visible icon buttons from being treated as empty ignored text.

The Windows accessibility test helper mocks AOT mode alongside its existing embedder API mocks, so its dummy asset paths work in the release test build. Refreshing Flutter's artifact cache removes these custom artifacts; reinstall them before building this fork again.

The separate CM access-key patch applies after the main engine patch. On Windows,
button/checkbox/text-field/tab semantics with an exact `Alt+X` hint (one uppercase ASCII letter)
expose that hint as UIA `AccessKey` and MSAA `accKeyboardShortcut`, using the
existing Chromium provider. Other hints and roles keep their original mapping.
This is the convention used by `CmAccessKey`, not a new stock Flutter API; it
requires only the rebuilt Windows DLL/import library, with no additional Dart
platform-kernel changes. `AccessibilityBridgeWindows.CmAccessKeysReachUiaAndMsaa`
tests both native properties, invalid hints and clearing the shortcut.

CM mnemonics use the same guarded callbacks as mouse actions, move focus to the
control, ignore repeat events, and apply only to focusable controls in the active
focus scope. Hidden/inactive session pages, disabled actions and covered dialog
routes do not respond. Button labels underline the mnemonic; permission icons
display the underlined letter. Alt+Space and Alt+F4 remain system operations.

The same binding now covers the Windows home connection controls, settings
categories and common settings actions, server fields, password prompts and
standard dialog buttons. Settings options retain normal Tab/arrow navigation;
ordinary switches and checkboxes do not each get an access key. Existing field
and tab focus nodes retain their owner and lifecycle. Text-field mnemonics only
focus the field; category mnemonics select and focus the category. Standard
button semantics are merged so the name, role, action and shortcut share one
native node. Locked settings and inactive pages remain excluded from focus and
cannot respond to mnemonics. Main buttons use Alt+N to connect, while dialogs use
Alt+O to confirm, Alt+C to cancel and Alt+X to close, avoiding same-dialog conflicts.
