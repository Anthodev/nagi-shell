import Quickshell
import "qml"

ShellRoot {
    KWinVirtualDesktopAdapter {
        id: virtualDesktops
        helperPath: Quickshell.shellPath("build/nagi-kwin-virtual-desktops")
    }

    CompactClock {
        id: clock
    }

    IslandStateCoordinator {
        id: islandState
    }

    WeatherAdapter {
        id: weather
    }

    MediaAdapter {
        id: media
    }

    AudioAdapter {
        id: audio
        bridgePath: Quickshell.shellPath("build/nagi-pipewire-audio")
    }
    ConnectivityAdapter {
        id: connectivity
        helperPath: Quickshell.shellPath("build/nagi-connectivity")
    }

    ReducedMotion {
        id: motion
    }

    IslandSurfaceHost {
        coordinator: islandState
        virtualDesktops: virtualDesktops
        clock: clock
        weather: weather
        media: media
        reducedMotion: motion.active
    }
}
