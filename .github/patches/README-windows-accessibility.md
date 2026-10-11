# Windows accessibility patches

Use Flutter SDK 3.24.5 with Flutter engine 3.24.4 (`db49896cf25ceabc44096d5f088d86414e05a7aa`), matching RustDesk's Windows engine release build. Do not apply these changes to a newer SDK or reuse the old engine DLL.

`flutter-engine-3.24.4-accessibility.diff` adds a distinct `hasSelectedState` flag, only exposes Windows selection state when declared, keeps tooltip-only controls in the accessibility tree, and excludes ignored leaves from Windows accessibility hit testing. It includes RustDesk's existing `ClearCurrent` and `hex_codec.h` build compatibility changes. Apply it to a clean engine checkout after syncing dependencies:

```powershell
git -C $engineSource apply E:\rustdesk\.github\patches\flutter-engine-3.24.4-accessibility.diff
Set-Location (Split-Path $engineSource)
python .\flutter\tools\gn --runtime-mode=release --enable-unittests
ninja -C .\out\host_release flutter_windows flutter_windows_unittests
.\out\host_release\flutter_windows_unittests.exe --gtest_filter="AccessibilityBridgeWindows.*"
```

Apply `flutter-3.24.5-selection-state.diff` to the Flutter SDK root. The matching engine's `lib/ui/semantics.dart` and rebuilt platform kernel artifacts must also replace the SDK's cached UI declarations and patched SDK artifacts. Updating only the Dart source in `bin/cache/pkg/sky_engine` does not update the compiled platform kernel.

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
