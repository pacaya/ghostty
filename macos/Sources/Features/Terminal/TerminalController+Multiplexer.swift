import AppKit
import Darwin
import GhosttyKit

/// Tab and window close confirmation that ignores terminal multiplexers.
///
/// Closing a surface hangs up its PTY. A multiplexer client in the foreground
/// detaches on hangup while its server keeps the session alive, so there is
/// nothing to lose and no reason to ask for confirmation.
extension TerminalController {
    /// Foreground process names whose sessions survive the surface closing.
    private static let multiplexerProcessNames: Set<String> = [
        "tmux",
        "zellij",
        "screen",
        "abduco",
        "dtach",
    ]

    /// True if closing this controller's tab or window should ask for
    /// confirmation. A surface that only needs confirmation because a
    /// multiplexer is in the foreground does not count.
    var tabNeedsCloseConfirmation: Bool {
        let confirmAlways = ghostty.config.confirmCloseSurface == "always"
        return surfaceTree.contains { surface in
            guard surface.needsConfirmQuit else { return false }
            if confirmAlways || surface.readonly { return true }
            return !Self.isRunningMultiplexer(surface)
        }
    }

    private static func isRunningMultiplexer(_ view: Ghostty.SurfaceView) -> Bool {
        guard let pid = view.surfaceModel?.foregroundPID,
              let pid = pid_t(exactly: pid) else { return false }

        // proc_name fails with ENOMEM unless the buffer fits the full
        // 2 * MAXCOMLEN name field.
        var buf = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        guard proc_name(pid, &buf, UInt32(buf.count)) > 0 else { return false }
        return multiplexerProcessNames.contains(String(cString: buf))
    }
}

extension Ghostty.Config {
    /// The raw `confirm-close-surface` value: "true", "false", or "always".
    var confirmCloseSurface: String {
        guard let config = self.config else { return "true" }
        var v: UnsafePointer<Int8>?
        let key = "confirm-close-surface"
        guard ghostty_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else { return "true" }
        guard let ptr = v else { return "true" }
        return String(cString: ptr)
    }
}
