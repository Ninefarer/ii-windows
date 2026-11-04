# Windows-native end4 development branch

This branch is a Windows-first development preview, based on the pinned Quickshell and ii sources in `sources.lock`. It integrates the working glass renderer and distance-field text into the shell, instead of depending on theme installers. It is not a completed rewrite or a published release.

## What changed

- New installs default to end4-pC. Other styles and existing explicit choices remain available.
- Shared text labels and editable fields use a selectable rendering policy: Automatic selects distance fields on Windows, while Linux keeps native raster rendering. Both Settings layouts offer distance, native and curve choices. Fonts, icon glyphs, display scaling and font sizes are not forced.
- A single `DesktopBackground` service resolves wallpaper ownership and gates wallpaper writes, video playback and glass source availability. `auto` preserves the old draw-own-wallpaper preference. Explicit owners are Windows, ii and an external wallpaper app.
- External mode stops ii's wallpaper setter and per-desktop synchronization paths from competing with another app. It also stops ii's video layer and preview image. Desktop cards become translucent rather than refracting a stale Windows image. **It does not add live Wallpaper Engine refraction.**
- The hidden static glass source decodes at the current Qt window DPR, instead of limiting its image to logical pixel dimensions.
- Shell updates, cached release information, the installer and bug-report links belong to `Ninefarer/ii-windows`. Update cache entries from another distribution are discarded. Native previews must not silently route users back to the upstream build.
- Windows deployment omits 30 Linux executable helpers (107,530 bytes in the current locked source). It preserves the emoji data stored in `defaults/windows/fuzzel-emoji.sh`, PowerShell helpers, shaders and terminal color data. `SHELL-CONTENTS.json` records included and omitted files.
- The preview workflow builds an x64 package and setup executable, runs installer tests, and runs the existing Windows smoke harness. It uploads artifacts and never publishes or merges a release.

## Architecture audit

`WINDOWS-AUDIT.json` inventories 837 QML files, 221 files with Windows platform branches and 201 Linux-command reference sites. This is an inventory, not proof that those commands run on Windows. Reachability review is required for each removal. The existing native backend is substantial: its Core Audio, WinRT media, WlanAPI, hotkey, AppBar, desktop host, virtual desktop and notification implementations are retained.

| Area | Evidence | Current action / remaining work |
|---|---|---|
| Desktop hosting | `src/windows/desktop_host.cpp` handles multiple Explorer/WorkerW layouts and restacking; `panel_window.cpp` embeds desktop windows | Retain this native backend. Test Explorer restart, Win+D, DPI changes and third-party desktop apps on a real machine |
| Backdrop effects | `src/windows/blur.cpp::PanelBlur::updateActive` excludes embedded panels | Keep static refraction and live external sources separate; do not assume native DWM blur can be switched on for a child window |
| External capture | User's WPE renderer is a child of WorkerW under Progman; controlled Windows tests accept top-level capture and reject a child with E_INVALIDARG | Need a verified live-frame provider or a single-renderer windowed-source design. Whole-monitor/Progman capture risks capturing ii's own output and feedback |
| Typography | Shared StyledText requested native raster rendering; the user's comparison preferred distance fields at 1920x1080, 100% | Policy now belongs to the port. Other DPI/font combinations still need visual testing |
| DPI | `panel_window.cpp` reacts to screen scale changes and can recreate embedded windows | Retain it; fix the logical-resolution-only hidden glass image. Validate mixed-DPI transitions and monitor reconnects |
| Linux services | Most inspected services explicitly branch to native implementations or disable Linux processes | Retain shared QML APIs and compatibility namespaces. Remove Linux executable helpers from the Windows distribution, not arbitrary modules required by imports |
| First run / settings | Installer and QML each had an ii default; legacy wallpaper settings were independent booleans | Align end4 defaults and expose one ownership policy. Preserve legacy wallpaper intent through `auto` |
| Release identity | Setup, SelfUpdate and ProblemReport pointed at upstream; cache did not identify its repository | Fork endpoints and cache ownership are corrected before any preview is installed |
| Process invocation / Unicode | The standalone WPE query printed a path that PowerShell failed to collect | Future integration must use redirected native process output and explicit encoding. The theme test helper is not a native frame provider |
| Scope / cleanup | Linux-sounding module names such as Quickshell.Hyprland and Pipewire are implemented by Windows adapters | Names alone do not justify deletion. Removing adapters would break working native functionality |

## Tests and build

Local checks cover patch application/reapplication/reversal, rejection of modified base files without partial writes, actual wallpaper sync function behavior in managed/external modes, legacy owner migration, text-renderer defaults, distribution-aware update caches, and staged Windows package contents. The policy and staging checks run on Linux and Windows in CI. Rust installer tests and the full Windows smoke harness run in the candidate workflow.

The candidate workflow is `.github/workflows/native-candidate.yml`. Its jobs distinguish policy validation, native compilation/package production, installer-core tests and x64 runtime smoke tests. A QML compile pass is not a visual test. Hosted-runner results do not establish Wallpaper Engine interoperability or real-device performance.

The native source patch is `patches/ii/0001-windows-native-desktop.patch`, generated against the exact ii commit in `sources.lock`. Do not apply the old theme-level Install-Glass or Install-TextRendering scripts on top of a build from this branch; the corresponding features are integrated here.

To install a built artifact before there is a GitHub release, extract the artifact containing `ii-windows-setup.exe` and `ii-windows-26.1.1.1-native.1.zip`, then run:

```powershell
.\ii-windows-setup.exe --package .\ii-windows-26.1.1.1-native.1.zip --no-self-update
```

This uses the existing installer's local-package path. Review its changes and backup/repair controls before installation. The preview shares the upstream installation paths and settings; it is not a side-by-side installation. No install is performed automatically from this development session.

## Release gates

Before a public release: native compilation, installer and runtime checks must pass; source/license provenance must be packaged; restore/update behavior and existing settings must be checked; and a real Windows desktop must exercise end4 bar/dock/sidebar, focus, multi-monitor/DPI, Explorer restart, startup, and wallpaper ownership. Live external refraction remains an explicit blocker for claiming Wallpaper Engine glass support. Audio, HDR, battery and game-mode costs require measurements rather than assumptions.

A later theme revision should consume these stable port settings and capability states, instead of replacing shell files. Do not promise that the port can sample every other app's visual surface: the provider must report unavailable/unsupported sources honestly.
