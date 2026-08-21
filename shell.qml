import Quickshell
import "qml"

ShellRoot {
    KWinVirtualDesktopAdapter {
        id: virtualDesktops
        helperPath: Quickshell.shellPath("build/nagi-kwin-virtual-desktops")
    }

    IslandStateCoordinator {
        id: islandState
    }

    IslandSurfaceHost {
        coordinator: islandState
    }
}
