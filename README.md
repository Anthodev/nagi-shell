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

Hover the island to open the dashboard. On first launch, an independent onboarding window points to the configuration file and KDE shortcut settings. Close it with its visible action, `Escape`, or the window manager; Nagi records that dismissal under `${XDG_STATE_HOME:-$HOME/.local/state}/nagi-shell/`. Use Back or `Escape` to leave a focused island subview. Run `make stop` from another terminal to stop this checkout synchronously.

For startup diagnostics, use `make diagnose`, then inspect the checkout with `make instances` and `make logs`.

## Configuration

Nagi reads `${XDG_CONFIG_HOME:-$HOME/.config}/nagi-shell/theme.conf`. If the file is missing, Nagi creates this default without replacing an existing file:

```ini
[theme]
mode=wallpaper
accent=#5B6FF5
surface_opacity=0.96
font_family=Inter
outer_radius=16

[media]
enabled=true

[weather]
enabled=false
; Find a city's coordinates:
; https://nominatim.openstreetmap.org/ui/search.html
; latitude=48.85
; longitude=2.35

[clock]
format=24h
date_format=dddd, d MMMM
show_idle_date=false
```

| Section and key | Type and allowed value | Default | Effect |
|---|---|---|---|
| `theme.mode` | `wallpaper` or `accent` | `wallpaper` | Select the wallpaper-derived or fixed accent path |
| `theme.accent` | `#RRGGBB` or `#AARRGGBB` | `#5B6FF5` | Set the fixed accent or wallpaper-mode fallback |
| `theme.surface_opacity` | Decimal from `0.85` to `1.0` | `0.96` | Set only the outer island fill and shadow silhouette opacity |
| `theme.font_family` | Non-empty UTF-8 family name, at most 128 bytes | `Inter` | Set the presentation-wide family through `Theme.type.family` |
| `theme.outer_radius` | Whole logical pixels from `8` to `32` | `16` | Set the outer island and shadow radius |
| `media.enabled` | `true` or `false` | `true` | Show media and enable MPRIS observation |
| `weather.enabled` | `true` or `false` | `false` | Enable MET Norway weather only when both coordinates are valid |
| `weather.latitude` | Decimal from `-90` to `90` | unset | Set the explicit weather latitude |
| `weather.longitude` | Decimal from `-180` to `180` | unset | Set the explicit weather longitude |
| `clock.format` | `12h` or `24h` | `24h` | Select localized 12-hour time with AM/PM or `HH:mm` |
| `clock.date_format` | Non-empty Qt date pattern, at most 64 UTF-8 bytes | `dddd, d MMMM` | Format the date in Idle and Expanded presentations |
| `clock.show_idle_date` | `true` or `false` | `false` | Place the formatted date beside Idle time |

The strict parser accepts only these sections and keys. The file is limited to 4 KiB. Empty, oversized, duplicate, unknown, malformed, NUL-containing, non-finite, or out-of-range values reject the entire candidate. Valid changes apply atomically without restarting Quickshell. Invalid, partial, deleted, or unavailable content preserves the last valid snapshot. If Nagi cannot create the default, built-in defaults still start the shell.

`clock.date_format` follows [Qt's date format syntax](https://doc.qt.io/qt-6/qdate.html#toString-1). Common fields are `d`/`dd` for the day number, `ddd`/`dddd` for the localized weekday, `M`/`MM` for the month number, `MMM`/`MMMM` for the localized month name, and `yy`/`yyyy` for the year. Examples: `dd/MM/yyyy`, `yyyy-MM-dd`, and `ddd d MMM`. Put literal text inside single quotes. Empty patterns, control characters, and patterns longer than 64 UTF-8 bytes invalidate the candidate snapshot.

Wallpaper mode derives a bounded accent from the current Plasma static-image wallpaper, then falls back through `theme.accent` to `#5B6FF5`. Accent mode requires `theme.accent`. Both paths keep the existing contrast floors. Disabling media stops MPRIS observation. Disabling weather or omitting valid coordinates performs no weather request. Nagi never uses IP geolocation or calls a geocoding service.

## Controls and behavior

| Input | Result |
|---|---|
| Hover the Idle island | Open the Expanded dashboard |
| Dashboard device name | Open output/input device selection |
| Dashboard Tray, Launcher, History, Audio, Settings, or Session action | Open the corresponding view or KDE System Settings |
| Back or `Escape` | Return through the shared cancellation path |
| Session `Restart shell` | Soft-reload Nagi with `Quickshell.reload(false)` |
| Session Restart or Power off | Open the matching KDE confirmation path |

KDE lists these actions under **Nagi Shell**:

| Action | Proposed default |
|---|---|
| Open Dashboard | Unbound |
| Open Launcher | `Meta+Space`, only when available and no Nagi binding exists |
| Open System Tray | Unbound |
| Open Notification History | Unbound |
| Open Audio Controls | Unbound |
| Open Session Controls | Unbound |
| Open System Settings | Unbound |

Edit bindings in **System Settings -> Keyboard -> Shortcuts -> Nagi Shell**. Nagi reports active, conflicting, and unbound states but never removes or replaces another component's shortcut. If KRunner already owns `Meta+Space`, keep that binding or resolve the conflict in System Settings. The dashboard's Settings action remains available even when every global shortcut is unbound.

Backend-confirmed state is authoritative for audio, connectivity, brightness, and session operations. Pending and failure states do not report success.

## Privacy

Nagi has no telemetry. Desktop metadata, application history, pins, notifications, media state, audio devices, and wallpaper analysis stay local. Adapters bound untrusted text and keep raw D-Bus payloads, hardware identity, wallpaper paths, and backend errors out of the presentation.

Weather is opt-in. It sends coordinates truncated to two decimal places and the user's IP address to MET Norway, then stores a bounded local cache. No location label leaves the machine. Use the linked Nominatim web page to look up coordinates manually; Nagi does not contact Nominatim. Weather data comes from [MET Norway Locationforecast](https://api.met.no/weatherapi/locationforecast/2.0/documentation), transformed into compact Nagi Shell condition categories and licensed under [CC BY 4.0](https://api.met.no/doc/License). MET Norway provides no delivery SLA.

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
