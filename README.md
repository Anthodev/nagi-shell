<h1 align="center">Nagi Shell</h1>

<p align="center">
  <strong>A minimal, context-aware desktop island for KDE Plasma.</strong>
  <br>
  One floating surface for status, controls, feedback, launching, and authentication.
</p>

<p align="center">
  <a href="#about">About</a>
  ·
  <a href="#the-island">The island</a>
  ·
  <a href="#planned-features">Features</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-design%20phase-C99A2E" alt="Project status: design phase">
  <img src="https://img.shields.io/badge/KDE_Plasma-6.7+-1D99F3?logo=kde" alt="KDE Plasma 6.7 or newer">
  <img src="https://img.shields.io/badge/display_server-Wayland-6B7280" alt="Wayland">
  <img src="https://img.shields.io/badge/UI-Quickshell-8B5CF6" alt="Built with Quickshell">
</p>

> [!IMPORTANT]
> Nagi Shell is currently in the design phase. The interaction model and technical direction are documented, but there is no usable release yet.

## About

Nagi Shell is a desktop interaction hub for **KDE Plasma 6 on Wayland**, built with [Quickshell](https://quickshell.org/). Instead of reproducing a traditional panel filled with persistent widgets, it places a small floating island near the top of the display and shows only what matters in the current context.

At rest, the island stays quiet. On hover, it becomes a compact control surface. When the system reacts, it temporarily turns into an OSD or notification. The same surface also hosts the application launcher, session controls, and Polkit authentication.

The goal is simple: **one continuous object that observes, controls, launches, reacts, and authenticates without cluttering the desktop.**

## The island

```text
                         Nagi Shell
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
          ▼                   ▼                   ▼
        Idle                Hover             Interactive
   workspace · time     media · controls    launcher · session
   weather · media      audio · alerts      tray · notifications
          │                                       │
          └───────────────────┬───────────────────┘
                              ▼
                       Contextual feedback
                volume · brightness · workspace
                     notifications · Polkit
```

Every transition should feel like the same object changing purpose—not a collection of unrelated popups.

### State model

| State | Purpose | Examples |
|---|---|---|
| **Idle** | Show essential information at a glance | Workspace, clock, weather, active media |
| **Hover** | Reveal frequently used controls | Media player, audio, connectivity, recent notifications |
| **Transient** | Provide short-lived system feedback | Volume, brightness, workspace, incoming notification |
| **Interactive** | Complete a focused task | Application launcher, session menu, tray, notification history |
| **Modal** | Hold focus until a critical action is resolved | Polkit authentication |

A central priority system decides which state owns the island, queues lower-priority events when appropriate, and restores the previous state afterward.

## Design principles

- **Minimal at rest** — information that is not continuously useful does not belong in the idle state.
- **Context before density** — temporary takeovers replace permanent indicators.
- **One surface** — geometry and content morph instead of spawning disconnected windows.
- **Wayland native** — prefer KDE, KWin, D-Bus, PipeWire, MPRIS, and Quickshell integrations over X11 utilities.
- **Keyboard first** — launching and authentication must remain fast and natural without a pointer.
- **Purposeful motion** — restrained animation communicates state changes without becoming decoration.
- **Event driven** — signals and native services take precedence over polling and repeated shell commands.

## Planned features

### Compact status

- Current KDE virtual desktop
- 24-hour clock
- Minimal weather summary
- Active MPRIS media title with adaptive width

### Expanded controls

- Rich media controls and album artwork
- Clock, date, and compact calendar
- Wi-Fi and Bluetooth toggles
- PipeWire output and input volume controls
- Default audio output selection
- Pinned applications and system tray access
- Recent notifications

### Contextual takeovers

- Notifications with local history
- Volume and brightness feedback
- Workspace changes
- Application launcher with search, pinned and recent apps, and keyboard navigation
- Session actions: lock, suspend, log out, reboot, and power off
- Integrated, priority-locked Polkit authentication

## Platform and integrations

Nagi Shell targets a modern KDE Wayland desktop first:

| Layer | Target or role |
|---|---|
| Desktop | KDE Plasma 6.7+ |
| Compositor | KWin on Wayland |
| Shell toolkit | Quickshell |
| Audio | PipeWire |
| Media | MPRIS |
| Desktop state | KDE, KWin, and D-Bus APIs |
| Authentication | Polkit |
| Initial distribution target | Fedora 44+ |

Initial support targets one primary display while keeping the architecture open to future multi-monitor support.

## Architecture

The implementation is intended to remain modular and state-driven:

```text
Quickshell surface
       │
       ▼
central state manager ─── priority · queue · timeouts · restoration
       │
       ├── views and reusable components
       ├── contextual takeover views
       └── platform services
             ├── PipeWire and MPRIS
             ├── notifications and Polkit
             ├── KWin workspaces
             └── network, Bluetooth, apps, and session
```

Presentation, state coordination, configuration, and platform services should remain separate. Expensive views should load lazily, histories should be bounded, and continuously running work should be event-driven.

## Inspiration

Nagi Shell is inspired by the dynamic-island interaction model of **saneAspect**, while being designed specifically for KDE Plasma, KWin, and native Wayland workflows. It is not intended to be a clone: the project adapts the idea around KDE integrations and a strict state-priority model.
