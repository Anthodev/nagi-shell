pragma Singleton

import Quickshell
import QtQuick

// Semantic design-system boundary of the island. Visual components read these
// tokens instead of raw literals so contrast, sizing, and motion stay
// consistent and auditable in one place.
//
// Contrast floors, measured (WCAG 2.1 relative luminance) against the
// composited island surface (#080D16 at 96% alpha over black and over white
// desktops):
//   textPrimary   >= 16.2:1  AAA body text
//   textSecondary >= 10.2:1  AAA body text
//   textMuted     >=  5.8:1  AA body text
//   accentForeground = 7.4:1  against the accent fill
//   dangerForeground = 6.6:1  against the danger fill
//   focusRing     >=  8.8:1  non-text UI minimum is 3:1
//   accent        >=  7.19:1 control boundary against the surface
//   progressFill  =   5.9:1  against the progress track
// Never lower a token below its documented floor without re-measuring both
// composites. HDR readability relies on the same pairs: the surface is
// near-opaque and no primitive depends on blur or backdrop effects.
Singleton {
    id: root

    readonly property QtObject color: QtObject {
        readonly property color surface: "#F5080D16"
        readonly property color surfaceBorder: "#263448"
        readonly property color surfaceBorderHover: "#33465C"
        readonly property color surfaceBorderPressed: "#40566E"
        readonly property color controlFill: "#16222F"
        readonly property color controlFillHover: "#1E2E3E"
        readonly property color controlFillPressed: "#263A50"
        readonly property color textPrimary: "#EFF3F8"
        readonly property color textSecondary: "#B9C4D2"
        readonly property color textMuted: "#8494A6"
        readonly property color accent: "#7AA2F7"
        readonly property color accentHover: "#93B4F9"
        readonly property color accentPressed: "#6390EE"
        readonly property color accentForeground: "#0B1220"
        readonly property color danger: "#F26D7E"
        readonly property color dangerHover: "#F58594"
        readonly property color dangerPressed: "#E4576B"
        readonly property color dangerForeground: "#1F0A0E"
        readonly property color success: "#7BD88F"
        readonly property color warning: "#E8C268"
        readonly property color focusRing: "#8FB5FF"
        readonly property color progressTrack: "#1C2836"
    }

    readonly property QtObject spacing: QtObject {
        readonly property int xs: 4
        readonly property int sm: 8
        readonly property int md: 12
        readonly property int lg: 16
        readonly property int xl: 24
        readonly property int xxl: 32
    }

    readonly property QtObject radius: QtObject {
        readonly property int sm: 8
        readonly property int md: 12
        readonly property int pill: 9999
    }

    // Typography stays on the platform default family; only semantic sizes and
    // weights are tokenized until a concrete typeface decision exists.
    readonly property QtObject type: QtObject {
        readonly property int caption: 11
        readonly property int body: 13
        readonly property int title: 15
        readonly property int weightRegular: Font.Normal
        readonly property int weightMedium: Font.Medium
        readonly property int weightSemibold: Font.DemiBold
    }

    readonly property QtObject size: QtObject {
        // Minimum compact idle width; the live island width follows visible content.
        readonly property int islandIdleWidth: 120
        readonly property int islandIdleHeight: 36
        // Compact idle caps keep one long label from stretching the pill.
        readonly property int islandIdleWorkspaceMaximumWidth: 96
        readonly property int islandIdleMediaMaximumWidth: 220
        readonly property int controlHeightSm: 26
        readonly property int controlHeightMd: 32
        readonly property int controlHeightLg: 38
        readonly property int iconSizeSm: 14
        readonly property int iconSizeMd: 18
        readonly property int iconSizeLg: 22
        readonly property int progressBarHeight: 4
        readonly property real progressIndeterminateSpan: 0.28
        readonly property int focusRingWidth: 2
        readonly property int focusRingGap: 2
        readonly property int hairlineWidth: 1
    }

    readonly property QtObject opacity: QtObject {
        // Disabled controls dim as a whole and lose their border affordance,
        // so the state rides on luminance and flattening, never hue alone.
        readonly property real disabled: 0.45
    }

    readonly property QtObject motion: QtObject {
        readonly property int durationFast: 100
        readonly property int durationNormal: 180
        readonly property int durationSlow: 280
        readonly property int easingStandard: Easing.OutCubic
        readonly property int easingEmphasized: Easing.InOutCubic
    }
}
