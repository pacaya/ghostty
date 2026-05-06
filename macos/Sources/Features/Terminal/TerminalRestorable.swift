import Cocoa

protocol TerminalRestorable: Codable {
    static var selfKey: String { get }
    static var versionKey: String { get }
    static var version: Int { get }
    /// Minimum version that can be decoded safely
    static var minimumVersion: Int { get }
    init(copy other: Self)

    /// Returns a base configuration to use when restoring terminal surfaces.
    /// Override this to provide custom environment variables or other configuration.
    var baseConfig: Ghostty.SurfaceConfiguration? { get }
}

extension TerminalRestorable {
    static var minimumVersion: Int { version }
}

extension TerminalRestorable {
    static var selfKey: String { "state" }
    static var versionKey: String { "version" }

    private var debugDescription: String {
        withUnsafePointer(to: self) { ptr in
            "<\(ptr)>[version: \(Self.version)]"
        }
    }

    /// Default implementation returns nil (no custom base config).
    var baseConfig: Ghostty.SurfaceConfiguration? { nil }

    init?(coder aDecoder: NSCoder) {
        // If the version doesn't match then we can't decode. In the future we can perform
        // version upgrading or something but for now we only have one version so we
        // don't bother.
        let current = aDecoder.decodeInteger(forKey: Self.versionKey)
        guard current >= Self.minimumVersion else {
            AppDelegate.logger.error("error restoring terminal: version not supported: expected=\(Self.minimumVersion, privacy: .public), got=\(current, privacy: .public)")
            return nil
        }

        guard let v = aDecoder.decodeObject(of: CodableBridge<Self>.self, forKey: Self.selfKey) else {
            AppDelegate.logger.error("error restoring terminal: decode failed")
            return nil
        }

        self.init(copy: v.value)
    }

    func encode(with coder: NSCoder) {
        coder.encode(Self.version, forKey: Self.versionKey)
        coder.encode(CodableBridge(self), forKey: Self.selfKey)

        AppDelegate.logger.debug("saved terminal state: \(debugDescription)")
    }
}

/// Main-actor context used during `NSWindowRestoration` to pass per-leaf project
/// config from `TerminalRestorableState.init(from:)` into `SurfaceView.init(from:)`.
/// Safe because window restoration runs serially on the main actor and clears
/// the context as soon as the surface tree has been decoded.
@MainActor
enum SurfaceRestoreContext {
    static var leafConfigs: [UUID: ProjectLeafEditorFields] = [:]
}

/// The state stored for terminal window restoration.
final class TerminalRestorableState: TerminalRestorable {
    static var version: Int { 7 }
    static var minimumVersion: Int { 5 }

    var focusedSurface: String? {
        internalState.focusedSurface
    }
    var surfaceTree: SplitTree<PaneLeaf> {
        internalState.surfaceTree
    }
    var effectiveFullscreenMode: FullscreenMode? {
        internalState.effectiveFullscreenMode
    }
    var tabColor: TerminalTabColor? {
        internalState.tabColor
    }
    var titleOverride: String? {
        internalState.titleOverride
    }

    /// Internal State we use to perform unit tests
    ///
    /// Since we can't really change the type of `TerminalRestorableState`
    /// due to `CodableBridge<TerminalRestorableState>` supporting secure coding,
    /// we use an internal type to perform migration and tests
    private let internalState: InternalState<PaneLeaf>

    /// The associated project ID, if this tab is linked to a saved project.
    /// Optional field added without version bump — old state decodes with nil.
    let projectId: UUID?
    /// Per-leaf project config (initialInput, environmentVariables) keyed by
    /// SurfaceView UUID. Optional field added without version bump — old state
    /// decodes with an empty dict.
    let leafConfigs: [UUID: ProjectLeafEditorFields]

    init(from controller: TerminalController) {
        self.internalState = .init(from: controller)
        let project = controller.projectId.flatMap { id in
            MainActor.assumeIsolated { ProjectStore.shared.projects.first { $0.id == id } }
        }
        self.projectId = project?.id
        // Only persist leaves that actually have something to restore.
        self.leafConfigs = project?.layoutRoot.editorFieldsByLeafID().filter { _, fields in
            !(fields.initialInput?.isEmpty ?? true) || !fields.environmentVariables.isEmpty
        } ?? [:]
    }

    required init(copy other: TerminalRestorableState) {
        self.internalState = other.internalState
        self.projectId = other.projectId
        self.leafConfigs = other.leafConfigs
    }

    private enum CodingKeys: String, CodingKey {
        case projectId
        case leafConfigs
    }

    /// Custom decode to populate `SurfaceRestoreContext.leafConfigs` before
    /// `surfaceTree` is decoded inside `InternalState` — that's when
    /// `PaneLeaf.init(from:)` fires for each leaf and the surface needs
    /// to read its per-leaf project config.
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
        let encodedLeafConfigs = try container.decodeIfPresent(
            [UUID: ProjectLeafEditorFields].self, forKey: .leafConfigs) ?? [:]

        // Prefer the live project store so edits take effect on the next
        // restore. Fall back to the encoded snapshot when the project has
        // been deleted.
        let leafConfigs: [UUID: ProjectLeafEditorFields]
        if let projectId,
           let project = MainActor.assumeIsolated({
               ProjectStore.shared.projects.first { $0.id == projectId }
           }) {
            leafConfigs = project.layoutRoot.editorFieldsByLeafID().filter { _, fields in
                !(fields.initialInput?.isEmpty ?? true) || !fields.environmentVariables.isEmpty
            }
        } else {
            leafConfigs = encodedLeafConfigs
        }
        self.leafConfigs = leafConfigs

        MainActor.assumeIsolated {
            SurfaceRestoreContext.leafConfigs = leafConfigs
        }
        defer {
            MainActor.assumeIsolated {
                SurfaceRestoreContext.leafConfigs = [:]
            }
        }
        self.internalState = try InternalState<PaneLeaf>(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try internalState.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(projectId, forKey: .projectId)
        if !leafConfigs.isEmpty {
            try container.encode(leafConfigs, forKey: .leafConfigs)
        }
    }
}

enum TerminalRestoreError: Error {
    case delegateInvalid
    case identifierUnknown
    case stateDecodeFailed
    case windowDidNotLoad
}

/// The NSWindowRestoration implementation that is called when a terminal window needs to be restored.
/// The encoding of a terminal window is handled elsewhere (usually NSWindowDelegate).
class TerminalWindowRestoration: NSObject, NSWindowRestoration {
    static func restoreWindow(
        withIdentifier identifier: NSUserInterfaceItemIdentifier,
        state: NSCoder,
        completionHandler: @escaping (NSWindow?, Error?) -> Void
    ) {
        // Verify the identifier is what we expect
        guard identifier == .init(String(describing: Self.self)) else {
            completionHandler(nil, TerminalRestoreError.identifierUnknown)
            return
        }

        // The app delegate is definitely setup by now. If it isn't our AppDelegate
        // then something is royally fucked up but protect against it anyhow.
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            completionHandler(nil, TerminalRestoreError.delegateInvalid)
            return
        }

        // If our configuration is "never" then we never restore the state
        // no matter what. Note its safe to use "ghostty.config" directly here
        // because window restoration is only ever invoked on app start so we
        // don't have to deal with config reloads.
        if appDelegate.ghostty.config.windowSaveState == "never" {
            AppDelegate.logger.warning("skip restoration: window-save-state=never")
            completionHandler(nil, nil)
            return
        }

        // Decode the state. If we can't decode the state, then we can't restore.
        guard let state = TerminalRestorableState(coder: state) else {
            completionHandler(nil, TerminalRestoreError.stateDecodeFailed)
            return
        }

        // The window creation has to go through our terminalManager so that it
        // can be found for events from libghostty. This uses the low-level
        // createWindow so that AppKit can place the window wherever it should
        // be.
        let c = TerminalController.init(
            appDelegate.ghostty,
            withSurfaceTree: state.surfaceTree)
        guard let window = c.window else {
            completionHandler(nil, TerminalRestoreError.windowDidNotLoad)
            return
        }

        // Restore our tab color and avoid unnecessary `invalidateRestorableState` calls
        if let tabColor = state.tabColor {
            (window as? TerminalWindow)?.tabColor = tabColor
        }

        // Restore the tab title override
        c.titleOverride = state.titleOverride

        // Drop dangling project IDs: the referenced project may have been
        // deleted while this window's state was dormant.
        if let pid = state.projectId,
           MainActor.assumeIsolated({ ProjectStore.shared.projects.contains(where: { $0.id == pid }) }) {
            c.projectId = pid
        }

        // Setup our restored state on the controller
        // Find the focused surface in surfaceTree
        if let focusedStr = state.focusedSurface {
            var foundView: Ghostty.SurfaceView?
            for leaf in c.surfaceTree {
                guard let surface = leaf.terminal else { continue }
                if surface.id.uuidString == focusedStr {
                    foundView = surface
                    break
                }
            }

            if let view = foundView {
                c.focusedSurface = view
                restoreFocus(to: view, inWindow: window)
            }
        }

        completionHandler(window, nil)
        guard let mode = state.effectiveFullscreenMode, mode != .native else {
            // We let AppKit handle native fullscreen
            return
        }
        // Give the window to AppKit first, then adjust its frame and style
        // to minimise any visible frame changes.
        c.toggleFullscreen(mode: mode)
    }

    /// This restores the focus state of the surfaceview within the given window. When restoring,
    /// the view isn't immediately attached to the window since we have to wait for SwiftUI to
    /// catch up. Therefore, we sit in an async loop waiting for the attachment to happen.
    private static func restoreFocus(to: Ghostty.SurfaceView, inWindow: NSWindow, attempts: Int = 0) {
        // For the first attempt, we schedule it immediately. Subsequent events wait a bit
        // so we don't just spin the CPU at 100%. Give up after some period of time.
        let after: DispatchTime
        if attempts == 0 {
            after = .now()
        } else if attempts > 40 {
            // 2 seconds, give up
            return
        } else {
            after = .now() + .milliseconds(50)
        }

        DispatchQueue.main.asyncAfter(deadline: after) {
            // If the view is not attached to a window yet then we repeat.
            guard let viewWindow = to.window else {
                restoreFocus(to: to, inWindow: inWindow, attempts: attempts + 1)
                return
            }

            // If the view is attached to some other window, we give up
            guard viewWindow == inWindow else { return }

            inWindow.makeFirstResponder(to)

            // If the window is main, then we also make sure it comes forward. This
            // prevents a bug found in #1177 where sometimes on restore the windows
            // would be behind other applications.
            if viewWindow.isMainWindow {
                viewWindow.orderFront(nil)
            }
        }
    }
}

