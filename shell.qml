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

    IslandSurfaceHost {
        coordinator: islandState
    }
}
