# Desktop composition investigation

This records source findings for the next native rendering milestone. It is not
a claim that live external glass works in the current preview.

## Confirmed constraints

At the locked Quickshell source plus our native patches:

- `WinPanelWindow::wantsEmbedding()` embeds background/bottom panels that do
  not request keyboard focus or reserve desktop space.
- `updateEmbedding()` chooses Explorer's icon host or wallpaper host.
  `embedInto()` changes the window to a child and calls `SetParent`.
- `PanelBlur::updateActive()` explicitly excludes embedded panels.
- The existing blur implementation creates `WS_POPUP` backdrop windows,
  uses `CreateDesktopWindowTarget` and `CreateHostBackdropBrush`, and positions
  those top-level windows relative to the panel with `SetWindowPos`.
  Its placement and lifetime code assumes that hierarchy. Removing the embedded
  guard alone would not adapt it to Explorer's child-window stacking.
- The user's Wallpaper Engine DX11 renderer is a child under WorkerW/Progman.
  A controlled capture test accepted a top-level target and rejected a child
  target with E_INVALIDARG using the correct IGraphicsCaptureItem interface.
  This does not prove every Wallpaper Engine renderer is uncapturable.
- The current liquid-glass shader consumes a Qt scene texture. DWM backdrop
  blur does not by itself expose a texture that this shader can refract.

## Two capabilities need separate implementations

| Capability | Input | Open issue |
|---|---|---|
| Native background blur | Compositor content behind a desktop widget | Verify composition support and stacking for an Explorer child without moving the wallpaper app or losing desktop behavior |
| Live liquid refraction | An unoccluded wallpaper texture for the same frame | Obtain a supported frame source and bridge it into Qt without capturing ii itself |

A successful native blur experiment must not automatically advertise liquid
refraction support. A second windowed Wallpaper Engine instance can supply a
capture target, but adds rendering cost and can drift from the desktop instance;
it is not a synchronized integration.

## Next implementation boundary

Keep ownership in `DesktopBackground` and the native wallpaper write policy.
Introduce frame-source capabilities only when a provider exists: availability,
source kind, pixel size, device-pixel ratio, frame freshness, and a failure reason.
Loss of the source must clear its texture and fall back to translucency.
Do not substitute a cached Windows wallpaper image for an external live source.

First use an isolated native probe to establish whether an Explorer-child
composition target can blur the actual animated desktop. Check both existing
backdrop mechanisms, input pass-through, clipping, and teardown. If that fails,
record the unsupported capability rather than enabling topmost desktop windows.
For liquid refraction, evaluate a single-renderer source whose frames feed both
the visible wallpaper and glass; do not present independent playback as matching
frames. Keep experimental code out of the default shell until those claims are
verified.

## Acceptance evidence

Record Windows build, GPU/driver, renderer type, resolution and scale. Test an
animated high-contrast wallpaper so stale/static sources are obvious. Verify
Win+D, ordinary application occlusion, desktop icons and clicks, Explorer
restart, monitor disconnect/reconnect, mixed DPI, sleep/resume and shutdown.
Check for recursive feedback and stale frames; measure CPU/GPU use with the
effect enabled and disabled. Hosted smoke tests alone cannot establish this.
