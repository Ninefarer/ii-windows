# Experimental desktop widget glass

This fork applies `patches/ii/0001-windows-widget-glass.patch` to the ii revision in `sources.lock`. It ports end4-pC's FrostedGlass/liquidLens rendering into supported desktop cards on Windows. It is experimental and disabled by default.

## Enable

In a build made from this branch, open Settings → Background and enable **Glass widget backgrounds**, or use the same switch in the desktop widget menu. Both ii and end4-pC Settings layouts expose it. Start with a single still wallpaper using Fill/crop mode. Disable the switch to return to the Windows port's original card backgrounds.

This is a build integration, not a downloadable installer release. An ordinary upstream ii-windows install will not acquire the patch from this repository automatically. The full Build workflow can produce packages from this branch; no release is published by this change. The separate Honkai theme pack's `Install-Glass.ps1` should not be applied to a build which already contains this patch.

## Rendering

The Windows port can put desktop widgets in their own QQuickWindow while Explorer or a native video surface owns the visible wallpaper. The original cards explicitly disable their ShaderEffectSource-based blur on Windows. A capture in one QQuickWindow cannot reliably sample an item in the other.

The patch creates an invisible, crop-filled wallpaper Image inside WidgetCanvas, which follows the canvas into the widget window. All existing desktop widget wallpaper references point to that image on Windows. Supported WidgetCard instances use the upstream FrostedGlass component and liquidLens shader, with transparent card backgrounds. Resource and world-clock card color overrides respect glass visibility. Missing images retain the original solid card fill.

The renderer includes the shader source and an upstream precompiled qsb containing HLSL for Qt's Direct3D backend. It does not require DWM backdrop blur or Windows Transparency effects for the glass cards. Native window effects, the bar/dock, and the shell's Linux rendering path are otherwise retained.

## Limits and verification

- Video wallpaper samples `background.thumbnailPath`, a still image, rather than decoding the video twice. Refraction therefore does not follow video motion. In the Honkai preset the idle image differs from the video: select the still wallpaper for matching refraction.
- Supported cards include calendar, weather, user, media, resources and the 2x2 world clock. Independently drawn surfaces such as the 4x1 clock tiles and pixel clock are outside this patch.
- Collages, spanning, non-Fill crop modes, wallpaper shapes and parallax can disagree with the sampled image. Different monitor aspect ratios need a Windows visual check.
- Per-card texture captures and haze add GPU work. No Windows rendering, performance or stability result is claimed yet.
- Glass settings remain available in `background.widgets.glass`: `enable`, `tint`, `tintStrength`, `rimWidth`, `pull`, `split`, `haze`, `vividness`, and `sheen`. Defaults match upstream end4-pC. The UI exposes the enable switch.

`tools/test-ii-patches.py ii` checks application against the locked shell revision, idempotence, rejection of modified source before partial writes, reverse application, inclusion of new files in git-based package enumeration, all sixteen widget wallpaper references, settings entry points and HLSL shader content. The Shell patches workflow runs those tests on Linux and Windows. These checks do not replace the full Build workflow's QML compile smoke checks or a real desktop render test.

`tools/apply-ii-patches.py ii` checks the whole series before applying and stages it using `git apply --index`, so `git ls-files` includes newly added QML/shader files in deployment and smoke enumeration. It deliberately leaves staged changes in the dependency checkout. Apply only to a dedicated checkout/worktree; a modified target file is rejected. Already applied patches are accepted. Full Build and smoke jobs apply the same series, and local `tools/deploy-ii.sh` also applies it before enumerating shell files.

Before updating `sources.lock`, rebase/regenerate this patch against the new ii source and run the tests. Do not suppress patch failures or copy older replacement QML files over a newer shell.

## Sources and licensing

Base shell: nunreasonable/dots-hyprland `be25075b35cb5f8cc8e6eb19a8d8da9561d1dcdc`.
FrostedGlass component and liquidLens shader: pctrade/end4-pC `6f461b427a223e4c61c25194764fa5e3192eb36b`. These GPL-3.0 sources are carried in the patch with the shader source alongside the binary, under this repository's GPL-3.0 license. See LICENSE and THIRD-PARTY.md.
