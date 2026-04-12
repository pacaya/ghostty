import AppKit

// MARK: Ghostty Delegate

/// This implements the Ghostty app delegate protocol which is used by the Ghostty
/// APIs for app-global information.
extension AppDelegate: Ghostty.Delegate {
    func ghosttySurface(id: UUID) -> Ghostty.SurfaceView? {
        for window in NSApp.windows {
            guard let controller = window.windowController as? BaseTerminalController else {
                continue
            }

            for leaf in controller.surfaceTree {
                guard let surface = leaf.terminal, surface.id == id else { continue }
                return surface
            }
        }

        return nil
    }
}
