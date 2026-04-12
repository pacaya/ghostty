import AppKit
import Foundation

/// IPC command for creating a browser pane via the external JSON-over-socket
/// protocol (`GhosttyIPCServer`).
///
/// Protocol shape:
/// ```json
/// {
///   "method": "pane.new-browser-split",
///   "params": {
///     "url": "https://example.com",
///     "direction": "right",
///     "source_surface": "0x68f757569b63f6b0"
///   }
/// }
/// ```
///
/// `source_surface` is optional. When provided, it must be the Zig-side u64
/// surface ID — the same value child processes see as `$GHOSTTY_SURFACE_ID`
/// — encoded as a hex string (matches Zig's `0x%016x` format). Decoding as
/// a string avoids JSON-number precision issues for u64. When omitted, the
/// key window's focused terminal leaf is used as the anchor.
enum BrowserIPCCommand {
    /// Decoded `new-browser-split` payload.
    struct NewBrowserSplitCommand: Decodable {
        let url: URL
        let direction: Direction
        let sourceSurfaceId: UInt64?

        enum CodingKeys: String, CodingKey {
            case url
            case direction
            case sourceSurfaceId = "source_surface"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.url = try c.decode(URL.self, forKey: .url)
            self.direction = try c.decode(Direction.self, forKey: .direction)
            if let hex = try c.decodeIfPresent(String.self, forKey: .sourceSurfaceId) {
                let trimmed = hex.hasPrefix("0x") || hex.hasPrefix("0X")
                    ? String(hex.dropFirst(2))
                    : hex
                guard let id = UInt64(trimmed, radix: 16), id != 0 else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .sourceSurfaceId,
                        in: c,
                        debugDescription: "source_surface must be a nonzero hex u64")
                }
                self.sourceSurfaceId = id
            } else {
                self.sourceSurfaceId = nil
            }
        }
    }

    /// Direction for the new browser split. Mirrors
    /// `SplitTree.NewDirection` but lives here so the IPC payload can be
    /// decoded independently of split-tree internals.
    enum Direction: String, Codable {
        case left
        case right
        case up
        case down

        var asNewDirection: SplitTree<PaneLeaf>.NewDirection {
            switch self {
            case .left: return .left
            case .right: return .right
            case .up: return .up
            case .down: return .down
            }
        }
    }

    /// Errors surfaced back to the IPC client if a browser split cannot be
    /// created.
    enum HandlerError: Error, CustomStringConvertible {
        case sourceSurfaceNotFound(UInt64)
        case noFocusedTerminal
        case splitInsertFailed
        case unsupportedURLScheme(String)

        var description: String {
            switch self {
            case .sourceSurfaceNotFound(let id):
                return String(format: "source surface not found: 0x%016llx", id)
            case .noFocusedTerminal:
                return "no focused terminal leaf to anchor browser split"
            case .splitInsertFailed:
                return "failed to insert browser split into tree"
            case .unsupportedURLScheme(let scheme):
                return "unsupported URL scheme: \(scheme)"
            }
        }
    }

    /// Allowed URL schemes for IPC-originated browser splits. Local
    /// same-user clients must not be able to load `file:`, `data:`, or
    /// other ambient-authority schemes through this channel.
    private static let allowedURLSchemes: Set<String> = ["http", "https", "about"]

    /// A resolved IPC source: the controller that owns the source leaf
    /// and the leaf itself. Only terminal leaves are valid sources — a
    /// browser-leaf ID in a `source_surface` param is rejected since
    /// the `pane.new-browser-split` command is designed to be issued
    /// from within a terminal.
    struct ResolvedSource {
        let controller: BaseTerminalController
        let leaf: PaneLeaf
    }

    /// Walk every controller's surface tree looking for a terminal `PaneLeaf`
    /// whose wrapped `Ghostty.SurfaceView` has the given Zig-side u64 surface
    /// ID. Browser leaves have no `SurfaceView` and are naturally skipped.
    @MainActor
    static func locateSourceLeaf(forZigId id: UInt64) -> ResolvedSource? {
        for window in NSApp.windows {
            guard let controller = window.windowController as? BaseTerminalController else { continue }
            for leaf in controller.surfaceTree {
                if leaf.terminal?.zigId == id {
                    return ResolvedSource(controller: controller, leaf: leaf)
                }
            }
        }
        return nil
    }

    /// Resolve the source leaf from the current key window when the IPC
    /// client doesn't (or can't) name a specific surface. The focused leaf
    /// must be a terminal — browser leaves are rejected because
    /// `pane.new-browser-split` is designed to be issued from inside a
    /// terminal pane. (`focusedLeaf` can legitimately return a browser leaf
    /// via its cache branch, hence the explicit `isTerminal` check.)
    @MainActor
    static func locateKeyWindowTerminalLeaf() -> ResolvedSource? {
        guard let window = NSApp.keyWindow,
              let controller = window.windowController as? BaseTerminalController,
              let leaf = controller.focusedLeaf,
              leaf.isTerminal
        else { return nil }
        return ResolvedSource(controller: controller, leaf: leaf)
    }

    /// Handle a decoded `new-browser-split` command.
    ///
    /// - Parameter command: The decoded payload.
    /// - Throws: `HandlerError` if the source surface cannot be located,
    ///   the URL scheme is not allowed, or the split cannot be created.
    @MainActor
    static func handle(_ command: NewBrowserSplitCommand) throws {
        // Scheme allowlist. Only http(s) and the single "about:blank"
        // target are permitted via IPC. This keeps a same-user local
        // client from loading file://, data://, or other schemes.
        let scheme = (command.url.scheme ?? "").lowercased()
        guard allowedURLSchemes.contains(scheme) else {
            throw HandlerError.unsupportedURLScheme(scheme.isEmpty ? "(none)" : scheme)
        }
        if scheme == "about" && command.url.absoluteString != "about:blank" {
            throw HandlerError.unsupportedURLScheme(command.url.absoluteString)
        }

        let resolved: ResolvedSource
        if let id = command.sourceSurfaceId {
            guard let found = locateSourceLeaf(forZigId: id) else {
                throw HandlerError.sourceSurfaceNotFound(id)
            }
            resolved = found
        } else {
            guard let found = locateKeyWindowTerminalLeaf() else {
                throw HandlerError.noFocusedTerminal
            }
            resolved = found
        }

        guard BrowserCommands.spawnBrowserSplit(
            from: resolved.controller,
            anchor: resolved.leaf,
            url: command.url,
            direction: command.direction.asNewDirection
        ) != nil else {
            throw HandlerError.splitInsertFailed
        }
    }
}
