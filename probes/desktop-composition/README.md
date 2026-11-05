# Wallpaper Engine desktop composition probe

This is a standalone Windows x64 diagnostic, not an installer or a proven
Wallpaper Engine integration. It does not change ii, its settings, Wallpaper
Engine's configuration, or the Windows wallpaper. Close its control window to
remove all probe rectangles.

Keep Wallpaper Engine running with an animated wallpaper. Open
`ii-desktop-glass-probe.exe`. Four rectangles appear near the bottom of the
primary monitor:

- **A, left:** a HostBackdropBrush in an Explorer child window, matching the
  desktop-widget hierarchy.
- **B, middle:** the existing backend's accent blur mechanism in an Explorer
  child window. This uses an undocumented Windows API and may be unsupported.
- **C, third:** a top-level HostBackdropBrush control for comparison. It is
  temporary and is not a proposed always-on-top desktop solution.

- **D, right:** a top-level HostBackdropBrush placed at `HWND_BOTTOM`, with no
  always-on-top flag. If visible, also test whether ordinary applications cover
  it and whether it survives Win+D appropriately. This evaluates an alternative
  desktop topology, not a verified replacement for ii's desktop hosting.

Observe whether each rectangle shows the **moving** wallpaper through blur,
the static Windows wallpaper, a black/clear area, or nothing. API acceptance in
the report does not establish correct visual behavior. Use **Copy report** to
share the API results along with your observation for A/B/C/D.

The report is saved at
`%LOCALAPPDATA%\ii-windows\diagnostics\desktop-composition-probe.txt`.
The **Re-run probes** button recreates only the probe's own windows. If Explorer
restarts, the probe removes its remaining rectangles; rerun once Explorer is
ready. There is no screen capture, duplicate wallpaper renderer, injection,
reparenting of another app's windows, or forced Explorer restart.

This tests **native backdrop blur**, not the theme's texture-based liquid-lens
distortion. If the child-window route works on a real desktop, it can guide a
proper embedded backdrop implementation in ii. A CI lifecycle pass checks only
creation/cleanup on a synthetic host owned by the probe; hosted runners do not
establish Wallpaper Engine compatibility.
