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
  <img src="https://img.shields.io/badge/status-alpha-F59E0B" alt="Alpha — not stable">
</p>

> [!IMPORTANT]
> Nagi Shell is **alpha software**. It is not stable and not yet suitable as a daily driver: expect breaking changes, incomplete features, and rough edges while the implementation is refined. It runs from a source checkout on its target KDE Plasma and Wayland platform and has no tagged release yet.

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
- **Adaptive geometry.** Content determines the island size. Compact height/padding and expanded screen fractions stay inside tested bounds; empty regions collapse, focused collections grow only as needed, and screen bounds cap the result. Horizontal and vertical overflow scroll independently and keep keyboard focus visible.
- **Useful Idle state.** Mandatory Clock plus optional Workspace, Weather, and Media stay in one fixed order inside a metrics-derived 44 to 48 px bar. Disabled or unavailable groups and separators collapse completely.
- **Current dashboard.** Media and a centered clock/date lead into large Wi-Fi and Bluetooth quick settings, active or attention tray applications, pinned launchers, two-column output/input audio, recent notifications, and the right navigation rail. Each connectivity tile keeps its backend-confirmed quick toggle and exposes a secondary path to its complete manager.
- **Focused tools.** Launcher, notification history, tray, audio-device selection, detailed Weather, and six session actions replace dashboard content inside the same island. Weather shows the shared current conditions, next 12 returned hours, and five returned days in a bounded scrolling view. History keeps a 480 px reading lane within a 512 px surface and shows up to five rows before scrolling. The tray subview lists every item in a scrollable grid, while the dashboard mirrors at most four active or attention items.
- **Native desktop integration.** KWin virtual desktops, PowerDevil brightness, PipeWire audio, MPRIS media, NetworkManager Wi-Fi management, BlueZ Bluetooth management, D-Bus session actions, desktop entries, KGlobalAccel, StatusNotifier items, notifications, KDE appearance, and one Plasma wallpaper service feed normalized adapters.
- **Local wallpaper management.** The Control Center shows common, mixed, and unsupported per-display state; indexes only approved local folders; renders lazy cached thumbnails; previews a static image without changing Theme; and applies it to every active display only after an explicit action and fresh readback.
- **Bounded live appearance.** Nagi Dark, OLED, Light, System, and reduced Custom inputs publish one contrast-checked semantic snapshot across every island and Nagi window. Nagi, System, Wallpaper, and Custom accents share one derivation path; optional blur keeps a readable plain-surface fallback.
- **Semantic icons.** Nagi icons, KDE action icons, and untinted application icons share one resolver/rendering path with a neutral fallback and adapt contrast to the current semantic surface; muted input has its own slashed-microphone shape.
- **Restrained motion.** Full, Reduced, and Minimal combine with KDE's animation preference by selecting the most restrictive scale. Minimal settles geometry, loaders, and focus synchronously.

## State model

| State | Observable purpose | Examples |
|---|---|---|
| **Idle** | Show compact, display-only status | Workspace, clock, optional weather and media |
| **Expanded** | Expose frequent controls and recent context | Media, connectivity, audio, pinned apps, notifications |
| **Interactive** | Complete one focused task | Launcher, History, Tray, Audio, Weather, Session |
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
| Runtime services | PipeWire, MPRIS, KDE D-Bus services, PowerDevil 6.7 or newer for brightness, and Plasma wallpaper analysis as available |

The [`Makefile`](Makefile) is the source of truth for versions, packages, helper builds, and commands.

## Install

Clone the development branch and install the Fedora dependencies printed by `make requirements`:

```bash
git clone --branch develop https://github.com/Anthodev/nagi-shell.git
cd nagi-shell
sudo dnf copr enable errornointernet/quickshell
sudo dnf install quickshell rsms-inter-fonts pipewire-devel glib2-devel kf6-kglobalaccel-devel qt6-qtbase-devel qt6-qtdeclarative-devel python3-dbus-next cmake
make requirements
```

### Scripted setup

From a cloned checkout, `sudo ./install.sh` performs the full setup on any distribution running KDE Plasma Wayland: it verifies prerequisites and offers the missing ones through the detected package manager, builds the native helpers, installs the tree under `/usr/share/nagi-shell` (`--dest` overrides this), registers the **Nagi Shell** section in KDE keyboard settings immediately, creates a private default `settings.conf` only when neither V2 settings nor a legacy `theme.conf` exists, enables session autostart, and installs a `nagi-shell` launcher wrapper plus **Nagi Control Center** desktop entry. The entry raises the existing same-process window or starts Nagi and then activates it. The wrapper also hands `org.freedesktop.Notifications` from plasmashell to Nagi for each session. It asks for confirmation before acting; see `./install.sh --help`.

`./uninstall.sh --dest /usr/share/nagi-shell` reverses everything: it stops the instance, removes the **Nagi Shell** shortcut category through the KGlobalAccel D-Bus API (never by editing raw config files), deletes the installation, launcher, desktop and autostart entries plus `~/.config/nagi-shell` and `~/.local/state/nagi-shell`, and offers a plasmashell restart so Plasma reclaims notification delivery.

### First use

Run the checkout in the foreground. `make launch` builds the native helpers and notification plugin before starting Quickshell.

```bash
make launch
```

Hover the island to open the dashboard. On first launch, an independent onboarding window explains the private versioned settings, Control Center, and KDE shortcut management. Close it with its visible action, `Escape`, or the window manager; Nagi records that dismissal under `${XDG_STATE_HOME:-$HOME/.local/state}/nagi-shell/`, and a missing or unwritable record simply means onboarding appears again later. Dashboard Settings opens the normal resizable Control Center in the same Nagi process. Its complete Island, Appearance, Clock & Date, Media, Weather, Notifications, Wi-Fi, Bluetooth, Displays, and About pages unload while closed; setting changes publish immediately through the shared settings snapshot. Wi-Fi discovery, Open/WPA Personal connection, explicit hidden networks, disconnect, and confirmed personal-profile removal use NetworkManager only; secrets clear after submission and remain outside Nagi settings and diagnostics. Bluetooth discovery runs only after explicit Scan and stops after 30 seconds or page close. Nagi-initiated pairing uses a scoped non-default BlueZ agent, trusts a completed pairing, attempts one connection, and supports confirmed connect, disconnect, and unpair without displacing Bluedevil. While Nagi runs, it acts as the session's freedesktop notification server.

For startup diagnostics, use `make diagnose`, then inspect the checkout with `make instances` and `make logs`.

## Configuration

Nagi owns one canonical file at `${XDG_CONFIG_HOME:-$HOME/.config}/nagi-shell/settings.conf`. Schema version `2` is a file-format version, not the product's internal V2 program name. New files use the private canonical template in `packaging/settings.conf`; valid legacy `theme.conf` values migrate once, byte-for-byte backup to `settings.conf.bak`, then the old file stops being active.

> [!WARNING]
> Weather is opt-in. Manual search sends the submitted city or postal text and your IP address to Open-Meteo; if it is unavailable, Nagi may send the same submitted search to the configured Nominatim endpoint. Confirmed forecasts send your IP address and four-decimal coordinates to MET Norway. Nagi stores no search history, uses no IP geolocation or automatic location tracking, and saves only the confirmed local label and coordinates. Accept this disclosure before searching or enabling Weather.

```ini
[settings]
schema_version=2

[appearance]
scheme=nagi-dark
accent_mode=wallpaper
custom_surface=#080D16
custom_text=#EFF3F8
custom_accent=#5B6FF5
surface_opacity=0.96
border_intensity=0
blur_enabled=false
motion=full
font_family=Inter
outer_radius=16

[island]
compact_height=46
compact_padding=24
expanded_width_percent=1
expanded_height_percent=1
show_workspace=true
show_weather=true
show_media=true
feedback_duration=normal
gaming_indicator=true

[clock]
format=24h
show_seconds=false
date_format=dddd, d MMMM
show_idle_date=false

[media]
enabled=true
compact_visible=true
dashboard_visible=true
player_policy=automatic
preferred_application=""

[notifications]
popups_enabled=true
do_not_disturb=false
critical_mode=bypass
dashboard_visible=true
history_visible=true

[weather]
enabled=false
consent=false
location_label=""
latitude=-
longitude=-
temperature_unit=auto
wind_unit=auto
refresh_preset=1h

[wallpaper]
roots=[]
```

| Section | Allowed values and bounds |
|---|---|
| `settings` | Exact integer `schema_version=2`; newer versions enter read-only compatibility mode |
| `appearance` | Scheme: `nagi-dark`, `nagi-oled`, `nagi-light`, `system`, or `custom`; accent: `nagi`, `system`, `wallpaper`, or `custom`; surface/text colors: `#RRGGBB`; custom accent: `#RRGGBB` or migrated `#AARRGGBB`; opacity: `0.85–1`; border: `0–1`; motion: `full`, `reduced`, or `minimal`; family: 1–128 UTF-8 bytes; radius: `8–32` |
| `island` | Compact height `44–48`, padding `16–32`, expanded width/height fractions `0.6–1`; fixed booleans for compact content and Gaming feedback; duration `short`, `normal`, or `long` |
| `clock` | Format `auto`, `12h`, or `24h`; seconds and Idle date booleans; date pattern `dddd, d MMMM`, `ddd, d MMM`, `yyyy-MM-dd`, `MM/dd/yyyy`, or `dd/MM/yyyy` |
| `media` | Integration, compact, and dashboard booleans; `automatic` or `preferred` player policy; preferred desktop-file ID up to 256 UTF-8 bytes |
| `notifications` | Popup, DND, dashboard, and history booleans; critical policy `bypass` or `silence` |
| `weather` | Enabled and consent booleans; label up to 128 UTF-8 bytes; latitude `-90–90`; longitude `-180–180`; temperature `auto`/`celsius`/`fahrenheit`; wind `auto`/`kmh`/`mph`/`ms`; refresh `15m`/`30m`/`1h`/`3h` |
| `wallpaper` | JSON array of at most eight unique user-approved absolute roots, each at most 1024 UTF-8 bytes; the default is empty |

Nagi never adds a wallpaper folder automatically. The Wallpaper page suggests the XDG Pictures wallpaper folder, commonly `~/Pictures/Wallpapers`, and KDE's shared `/usr/share/wallpapers` directory. Add either through the read-only folder dialog if you want it indexed. Browse image may preview and apply one validated file elsewhere without approving or copying its directory.

The complete file is capped at 32 KiB: eight bounded wallpaper roots consume at most 8 KiB, while every other scalar remains below 2 KiB, leaving editorial headroom without permitting unbounded input. Unknown, duplicate, empty, malformed, NUL-containing, non-finite, or out-of-range input rejects the complete snapshot; no consumer sees a per-field hybrid.

Valid UI changes publish one immutable generation immediately. Continuous controls persist after a bounded 180 ms debounce; a write failure rolls the complete snapshot back. Valid external replacements win atomically. Invalid, partial, unreadable, or removed content keeps `settings.conf.last-good`, retains the bad file, blocks ordinary writes, and requires explicit **Restore last-good** or **Reset defaults**. Recovery first saves invalid bytes to `settings.conf.invalid`. A newer schema is never rewritten or downgraded.

All settings files and backups use mode `0600` inside a mode-`0700` directory. A native writer rejects symlinks, directories, devices, FIFOs, foreign ownership, and unsafe replacements before performing private atomic writes. Wi-Fi passwords, Bluetooth codes, Polkit secrets, notification content, wallpaper thumbnails, provider responses, hardware IDs, and backend paths never enter settings, backups, diagnostics, or logs. Reset all affects settings only; it does not clear histories, caches, credentials, paired devices, saved networks, or user files.

`clock.date_format` accepts only the five validated patterns listed above. The Control Center presents them as bounded choices rather than accepting arbitrary Qt format strings.

## Data storage

Everything below stays on this machine; Nagi has no telemetry or sync.

**Launcher data.** Pins persist in `${XDG_CONFIG_HOME:-$HOME/.config}/nagi-shell/application-pins.json` and recency in `${XDG_STATE_HOME:-$HOME/.local/state}/nagi-shell/application-recency.json`. Both files hold versioned JSON with exact desktop-file IDs only — never names, commands, paths, or icons — capped at 8 ordered pins and 20 recent IDs. Search returns at most eight eligible results, and the viewport shows up to five rows before scrolling. An uninstalled application's pin stays dormant within the cap and returns only if the same ID is reinstalled; ineligible recency entries are pruned, and identities are never migrated when an application changes its desktop-file ID. A corrupt or oversized file starts that store empty and is replaced canonically at the next change. To recover manually, stop Nagi with `make stop` and move or remove the affected file; never edit either file while the shell runs.

**Notification history.** Memory-only: no history file or database exists, and history is lost entirely when the process exits. It keeps at most 50 records for at most 24 hours, newest first, with the four most recent mirrored on the dashboard. Transient notifications never enter history. Expired notifications remain as text-only records until evicted; dismissed, action-consumed, and sender-closed records are removed immediately. A separate safety cap of 50 tracked protocol notifications expires the lowest-ranked item deterministically under pressure, even critical or never-expiring ones. Notification actions remain disabled on current supported Quickshell versions.

**Weather cache.** One private record for the confirmed label-and-coordinate identity lives in Quickshell's per-shell cache directory as `weather.json`, written atomically and reused at startup. It holds one bounded MET Norway compact response for process-wide current, 12-hour, and five-day projections; it never duplicates the human-readable label. Refreshes honor provider expiry and conditional requests before the selected `15m`, `30m`, `1h`, or `3h` preference, with a ten-minute minimum gap, manual-refresh cooldown, Retry-After, and bounded backoff. Expired valid data is marked stale with age for at most six hours, then discarded. Disabling Weather or changing/clearing the confirmed location aborts work and clears the prior cache.

**Wallpaper cache.** Source images remain in their original folders. While the Wallpaper page is open, the helper indexes up to eight approved roots and decodes only visible or selected static images. Thumbnails use an 8 MiB memory LRU and a private atomic version-1 disk LRU capped at 64 MiB and 512 entries under `${XDG_CACHE_HOME:-$HOME/.cache}/nagi-shell/`. File-byte changes create a new cache identity; deleted and renamed files leave the live library model. Closing the page cancels indexing, queued thumbnail work, preview analysis, and its watchdog.

**Onboarding record.** First-launch dismissal persists under `${XDG_STATE_HOME:-$HOME/.local/state}/nagi-shell/`.

## Controls and behavior

| Input | Result |
|---|---|
| Hover the Idle island | Open the Expanded dashboard |
| Dashboard device name | Open output/input device selection |
| Dashboard Wi-Fi, right click or `Shift+Enter` | Open the Wi-Fi Control Center page on the initiating display |
| Dashboard Bluetooth, right click or `Shift+Enter` | Open the Bluetooth Control Center page on the initiating display |
| Dashboard Tray, Launcher, History, Audio, Settings, or Session action | Open the corresponding focused view or Nagi Control Center |
| Expanded or Tray application icon, primary/middle click | Dispatch the tray action and return the non-modal island to Idle |
| Expanded or Tray application icon, right click | Keep the island open while showing the native context menu; selecting an entry returns Idle, while dismissal preserves the current state |
| Accepted application launch or reliable external focus loss | Clear non-modal state and return directly to Idle |
| Back or `Escape` | Return through the shared cancellation path |

KDE lists these actions under **Nagi Shell**:

| Action | Proposed default |
|---|---|
| Open Dashboard | Unbound |
| Open Launcher | `Meta+Space`, only when available and no Nagi binding exists |
| Open System Tray | Unbound |
| Open Notification History | Unbound |
| Open Audio Controls | Unbound |
| Open Session Controls | Unbound |
| Open Control Center | Unbound |

Edit bindings in **System Settings -> Keyboard -> Shortcuts -> Nagi Shell**. Nagi reports active, conflicting, and unbound states but never removes or replaces another component's shortcut. If KRunner already owns `Meta+Space`, keep that binding or resolve the conflict in System Settings. The dashboard's right rail keeps the launcher reachable when no global shortcut is active, and its Settings action opens the same-process Control Center even when every binding is unbound.

Backend-confirmed state is authoritative for audio, connectivity, brightness, and session operations. Pending and failure states do not report success.

### Feedback timing

Transient feedback holds while its content is visible: notifications for 3 seconds, volume and brightness for 1.8 seconds, and workspace changes for 1.2 seconds. Feedback arriving mid-interaction waits briefly and is dropped — not replayed afterward — past 6 seconds for notifications, 3 seconds for volume and brightness, or 2 seconds for workspace changes. Repeated backend-confirmed values coalesce into one presentation. Authentication always outranks interactive views: requests raised during authentication are rejected rather than deferred, and completing it does not open a launcher or session action requested while it was locked.

### Session actions

The Session view offers exactly six actions. **Lock** locks the KDE session immediately and **Suspend** suspends the computer. **Restart shell** soft-reloads Nagi in place through `Quickshell.reload(false)`. **Log out**, **Restart**, and **Power off** open the matching KDE confirmation dialog and act only after you confirm there.

### Brightness

Brightness uses PowerDevil 6.7's `org.kde.ScreenBrightness` interface exclusively. Only displays PowerDevil enumerates there are controllable; Nagi requests no hardware privileges and never uses brightnessctl, ddcutil, sysfs, or another backend. Displays absent from PowerDevil cannot be adjusted from the island. External monitors may be only partially observable because PowerDevil supplies a label but no reliable screen identity — Nagi treats display entries as opaque, and their naming can change across replug or driver events. To troubleshoot, check that the PowerDevil brightness service responds and how many displays it enumerates; avoid sharing connector names, EDIDs, hardware labels, or raw D-Bus dumps, which identify your hardware without aiding diagnosis.

## Privacy

Nagi has no telemetry. Desktop metadata, application history, pins, notifications, media state, audio devices, wallpaper discovery, previews, and apply state stay local. Adapters bound untrusted text and keep raw D-Bus payloads, hardware identity, current wallpaper paths and digests, network payloads, coordinates, location labels, submitted searches, and backend errors out of presentation diagnostics and logs.

Weather is opt-in and performs no automatic location lookup. The Weather page repeats the disclosure before its explicit city/postal search. Search uses the keyless [Open-Meteo geocoding API](https://open-meteo.com/en/docs/geocoding-api), based on GeoNames and licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), while Nagi remains non-commercial. Service failure may use the switchable [Nominatim](https://nominatim.org/) fallback at no more than one request per second; its data is © OpenStreetMap contributors under [ODbL](https://www.openstreetmap.org/copyright). Forecasts use only [MET Norway Locationforecast](https://api.met.no/weatherapi/locationforecast/2.0/documentation), transformed into bounded Nagi condition categories and calculated feels-like values, under [NLOD 2.0 / CC BY 4.0](https://api.met.no/doc/License). MET Norway provides no delivery SLA.

Polkit credentials never enter the production shell because the backend is dormant. Synthetic presentation tests still enforce explicit submission and secret cleanup.

## Limitations

- Every connected display starts with an enabled island. Visibility and fallback selection are session-only because Quickshell 0.3.x exposes no reliable persistent display identity; Nagi never guesses from connector names, labels, serials, indexes, or geometry. Global shortcuts target the pointer screen, then the enabled fallback.
- One Interactive task or Modal flow exists across all islands. Notifications and confirmed output-volume feedback may appear on every eligible island, while workspace and brightness remain routed and sensitive flows never mirror.
- Wi-Fi manages Open and WPA Personal networks through NetworkManager. Captive portals, IP/DNS editing, VPN, Enterprise/EAP, certificates, hotspots, and complete profile administration remain in KDE.
- Bluetooth uses BlueZ for explicit bounded discovery, scoped Nagi-initiated pairing, connect, disconnect, and unpair. Codecs, audio profiles, service-authorization editing, file transfer, battery history, per-adapter tuning, and advanced reconnect policy remain in KDE/PipeWire.
- Wallpaper management accepts local static JPEG, PNG, WebP, and BMP files only. It has no downloads, remote gallery, video, animation, slideshow editor, file operations, or per-display assignment. Apply replaces every active display with the selected static image; a partial Plasma write may leave successful displays changed and is reported per display.
- Audio covers default output/input selection, volume, and mute. It has no per-application mixer.
- The dashboard has no calendar panel, pre-sized geometry, or hardware-monitoring view.
- External monitors may be only partially observable for brightness: PowerDevil supplies a label without a reliable screen identity, so display entries are opaque and their naming can change across replug or driver events.
- The Polkit view is presentation-only and dormant in production.
- Isolated virtual-KWin checks prove QML surface, focus, topology, scaling, and lifecycle contracts but cannot prove physical HDR/VRR, hardware behavior, or frame pacing at the monitor's real refresh rate. Missing physical evidence is reported rather than obtained through host-session mutation.

## Architecture

```text
shell.qml
   │
   ├── one PanelWindow per enabled live display
   │      ├── independent Idle / Expanded / focus / geometry
   │      ├── one globally exclusive focused or Modal task
   │      └── shared-event transient projections
   │
   ├── one IslandStateCoordinator
   │      └── per-surface records · global priority · mailbox · deadlines · restoration
   │
   ├── normalized QML adapters
   │      └── media · audio · connectivity · apps · tray · notifications · wallpaper
   │
   ├── one lazy Control Center
   │      └── fixed complete routes · lazy Wallpaper picker · shared services/settings
   │
   └── native helpers and runtime plugins
          └── pointer routing · KWin · PowerDevil · PipeWire · session · wallpaper · KGlobalAccel
```

Presentation consumes semantic theme roles and normalized adapter state. Native protocol details remain inside helpers and bridges. Rare views load lazily; histories, queues, caches, strings, and wallpaper analysis are bounded.

Changes must preserve the single process-wide coordinator, one service graph, normalized adapter boundary, semantic presentation layer, bounded lazy views, and native-helper isolation shown above.

## Quality assurance

```bash
make help
make format-check
make check
```

`make check` runs native, adapter, coordinator, deterministic service, Control Center activation, and QML tests, then exercises the real `PanelWindow` and normal-window scenarios inside disposable `kwin_wayland --virtual` sessions with private D-Bus and XDG state. `make test-wallpaper` covers traversal, decoder/cache bounds, QML normalization, Theme isolation, and helper restart; `make test-wallpaper-dbus` covers observation lifecycle and stale-work cancellation; `make test-wallpaper-service` covers mixed displays, file changes, partial apply/readback, external authority, and unload with two virtual outputs. Override `KWIN_TEST_SCALE`, `KWIN_TEST_OUTPUTS`, `KWIN_TEST_WIDTH`, and `KWIN_TEST_HEIGHT` for one topology, or set `KWIN_TEST_MATRIX=1` for the 100/125/150/200 percent matrix. Read-only live probes such as `make test-audio-live` and `make test-wallpaper-live` remain separate; state-changing host probes require explicit per-run authorization.

`qmllint-qt6` remains advisory because it cannot resolve the valid Quickshell `PanelWindow`. Runtime diagnostics and the focused checks are authoritative.

## Acknowledgements

Nagi Shell takes its initial island interaction idea from saneAspect, then adapts it to KDE Plasma, KWin, and a strict state-priority model.

## Contributing

Keep changes scoped, event-driven, keyboard accessible, and verified with the focused harnesses and isolated virtual-KWin surface gates. Open issues and pull requests against `develop`; run the relevant targets and `make check` before submission.
