<h1 align="center">Nagi Shell</h1>

<p align="center">
  <strong>A context-aware desktop island for KDE Plasma.</strong>
  <br>
  One Quickshell surface for status, controls, launching, and short-lived system feedback.
</p>

<p align="center">
  <a href="#about">About</a>
  ·
  <a href="#highlights">Highlights</a>
  ·
  <a href="#install">Install</a>
  ·
  <a href="#configuration">Configuration</a>
  ·
  <a href="#quality-assurance">QA</a>
</p>

<p align="center">
  <a href="https://github.com/Anthodev/nagi-shell/actions/workflows/checks.yml"><img src="https://github.com/Anthodev/nagi-shell/actions/workflows/checks.yml/badge.svg?branch=develop" alt="Repository checks"></a>
  <img src="https://img.shields.io/badge/Fedora-44+-51A2DA?logo=fedora" alt="Fedora 44 or newer">
  <img src="https://img.shields.io/badge/KDE_Plasma-6.7+-1D99F3?logo=kde" alt="KDE Plasma 6.7 or newer">
  <img src="https://img.shields.io/badge/Quickshell-0.3.0+-8B5CF6" alt="Quickshell 0.3.0 or newer">
</p>

> [!IMPORTANT]
> Nagi Shell runs from a source checkout on its target Fedora, KDE Plasma, and Wayland platform. It has no tagged stable release yet. Expect setup and behavior to change while the implementation is refined.

## About

Nagi Shell is a desktop island for **KDE Plasma 6 on Wayland**, built with [Quickshell](https://quickshell.org/). It replaces a row of persistent panel widgets with one content-sized object near the top of the display. The object stays compact at rest, expands for common controls, and changes content for focused tasks or system feedback.

```text
Idle ───────────────► Expanded ───────────────► Focused task
workspace · clock     media · clock/date        launcher · history
weather · media       connectivity · audio      tray · audio · session
       ▲                       │                         │
       └──────── restoration ◄─┴─ transient feedback ◄─┘
                         volume · brightness
                       workspace · notification
```

**The goal is one continuous desktop object, not a collection of unrelated popups.**

## Highlights

- **One real surface.** Idle, Expanded, focused subviews, and transients share one `PanelWindow`; a central coordinator owns priority, timeouts, preemption, and restoration.
- **Adaptive geometry.** Content determines the island size. Empty regions collapse, focused collections grow only as needed, and screen bounds cap the result. Horizontal and vertical overflow scroll independently and keep keyboard focus visible.
- **Useful Idle state.** A two-digit workspace badge, clock, optional weather, and active media fit a metrics-derived 44 to 48 px bar.
- **Current dashboard.** Media and a centered clock/date lead into large Wi-Fi and Bluetooth quick settings, active or attention tray applications, pinned launchers, two-column output/input audio, recent notifications, and the right navigation rail.
- **Focused tools.** Launcher, notification history, tray, audio-device selection, and six session actions replace dashboard content inside the same island.
- **Native desktop integration.** KWin virtual desktops, PowerDevil brightness, PipeWire audio, MPRIS media, D-Bus connectivity and session actions, desktop entries, KGlobalAccel, StatusNotifier items, notifications, and the Plasma wallpaper palette feed normalized adapters.
- **Semantic theme and icons.** A live theme snapshot provides contrast-checked roles. Nagi icons, KDE action icons, and untinted application icons share one resolver/rendering path with a neutral fallback; muted input has its own slashed-microphone shape.
- **Restrained motion.** Focused content enters and exits over 180 ms while the outer geometry interpolates over 300 ms. Reduced-motion preferences settle both layers and focus synchronously.

## State model

| State | Observable purpose | Examples |
|---|---|---|
| **Idle** | Show compact, display-only status | Workspace, clock, optional weather and media |
| **Expanded** | Expose frequent controls and recent context | Media, connectivity, audio, pinned apps, notifications |
| **Interactive** | Complete one focused task | Launcher, History, Tray, Audio, Session |
| **Transient** | Replace Idle with short-lived feedback | Notification, volume, brightness, workspace |
| **Modal** | Hold a normalized authentication presentation | Dormant Polkit UI seam only |

The Polkit presentation is implemented and tested with synthetic controllers, but production `shell.qml` does not register or inject a Polkit backend. KDE's existing authentication agent remains responsible for real requests.

## Requirements

| Layer | Requirement |
|---|---|
| Distribution | Fedora 44 or newer |
| Desktop | KDE Plasma 6.7 or newer, KWin, Wayland |
| Shell | Stable Quickshell 0.3.0 or newer from `errornointernet/quickshell` |
| UI font | Inter through `rsms-inter-fonts`; Fontconfig supplies fallbacks |
| Native build | C++20, Qt 6, PipeWire, GIO Unix, KF6 GlobalAccel, and CMake |
| Runtime services | PipeWire, MPRIS, KDE D-Bus services, and Plasma wallpaper services as available |

The [`Makefile`](Makefile) is the source of truth for versions, packages, helper builds, and commands.

## Install

Clone the development branch and install the Fedora dependencies printed by `make requirements`:

```bash
git clone --branch develop https://github.com/Anthodev/nagi-shell.git
cd nagi-shell
sudo dnf copr enable errornointernet/quickshell
sudo dnf install quickshell rsms-inter-fonts pipewire-devel glib2-devel kf6-kglobalaccel-devel qt6-qtbase-devel qt6-qtdeclarative-devel cmake
make requirements
```

### First use

Run the checkout in the foreground. `make launch` builds the native helpers and notification plugin before starting Quickshell.

```bash
make launch
```

Hover the island to open the dashboard. The launcher helper requests `Meta+Space`; if that shortcut conflicts or cannot register, open Launcher from the dashboard rail. Use Back or `Escape` to leave a focused subview. Run `make stop` from another terminal to stop this checkout synchronously.

For startup diagnostics, use `make diagnose`, then inspect the checkout with `make instances` and `make logs`.

## Configuration

Nagi reads `${XDG_CONFIG_HOME:-$HOME/.config}/nagi-shell/theme.conf`. Wallpaper mode is the default and falls back through the configured accent to the official `#5B6FF5` accent.

```ini
[theme]
mode=wallpaper
accent=#5B6FF5
```

| Mode | Behavior |
|---|---|
| `wallpaper` | Derive a bounded accent from the current Plasma static-image wallpaper; use `accent` as fallback |
| `accent` | Use the configured `#RRGGBB` or `#AARRGGBB` color |

The file is limited to 4 KiB and accepts only the two known keys in one `[theme]` section. Valid changes apply without restarting Quickshell. Invalid or partial writes preserve the last valid contrast-safe theme.

## Controls and behavior

| Input | Result |
|---|---|
| Hover the Idle island | Open the Expanded dashboard |
| `Meta+Space` when registered | Open Launcher and focus search |
| Dashboard device name | Open output/input device selection |
| Dashboard Tray, Launcher, History, or Session icon | Open that focused subview |
| Back or `Escape` | Return through the shared cancellation path |
| Session `Restart shell` | Soft-reload Nagi with `Quickshell.reload(false)` |
| Session Restart or Power off | Open the matching KDE confirmation path |

Backend-confirmed state is authoritative for audio, connectivity, brightness, and session operations. Pending and failure states do not pretend an operation succeeded.

## Privacy

Nagi has no telemetry. Desktop metadata, application history, pins, notifications, media state, audio devices, and wallpaper analysis stay local. Adapters bound untrusted text and keep raw D-Bus payloads, hardware identity, wallpaper paths, and backend errors out of the presentation.

Weather is opt-in at the adapter boundary. When configured, it sends coordinates truncated to two decimal places to MET Norway and stores a bounded local cache; its optional location label never leaves the machine. The production checkout currently leaves weather coordinates unconfigured, so it makes no weather request.

Polkit credentials never enter the production shell because the backend is dormant. Synthetic presentation tests still enforce explicit submission and secret cleanup.

## Limitations

- The runtime creates one island on the display Qt selects when the surface starts. It does not infer persistent output identity or provide a multi-display island set.
- Wi-Fi supports state and toggle only. Network selection is outside the island.
- Bluetooth supports adapter state and toggle only. Discovery, pairing, and device management are outside the island.
- Audio covers default output/input selection, volume, and mute. It has no per-application mixer.
- The dashboard has no calendar panel, pre-sized geometry, or hardware-monitoring view.
- The Polkit view is presentation-only and dormant in production.
- Headless checks do not replace final verification on a real KDE/KWin Wayland session, especially for rendering, multi-display behavior, HDR, and hardware integrations.

## Architecture

```text
shell.qml
   │
   ├── one PanelWindow and adaptive content host
   │      ├── Idle / Expanded
   │      ├── focused subviews
   │      └── transient replacement
   │
   ├── IslandStateCoordinator
   │      └── priority · deadlines · preemption · restoration
   │
   ├── normalized QML adapters
   │      └── media · audio · connectivity · apps · tray · notifications
   │
   └── native helpers and runtime plugin
          └── KWin · PowerDevil · PipeWire · session · wallpaper · KGlobalAccel
```

Presentation consumes semantic theme roles and normalized adapter state. Native protocol details remain inside helpers and bridges. Rare views load lazily; histories, queues, caches, strings, and wallpaper analysis are bounded.

Changes must preserve the single-surface coordinator, normalized adapter boundary, semantic presentation layer, bounded lazy views, and native-helper isolation shown above.

## Quality assurance

```bash
make help
make format-check
make check
```

`make check` runs the repository-defined native, adapter, coordinator, state, and headless surface checks. GitHub Actions runs display-independent checks and the real `PanelWindow` scenario under a software-rendered headless Wayland compositor. Live integration targets such as `make test-audio-live`, `make test-tray-live`, and `make test-wallpaper-live` are intentionally separate; `make help` lists the complete set.

`qmllint-qt6` remains advisory because it cannot resolve the valid Quickshell `PanelWindow`. Runtime diagnostics and the focused checks are authoritative.

## Acknowledgements

Nagi Shell takes its initial island interaction idea from saneAspect, then adapts it to KDE Plasma, KWin, and a strict state-priority model.

## Contributing

Keep changes scoped, event-driven, keyboard accessible, and verified against the actual KDE Wayland surface when they affect rendering or platform integration. Open issues and pull requests against `develop`; run the relevant focused targets and `make check` before submission.
