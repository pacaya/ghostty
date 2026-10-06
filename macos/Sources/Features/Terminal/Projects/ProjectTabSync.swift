import Combine
import Foundation

/// Keeps a linked tab's project in step with the live tab.
///
/// The owning `TerminalController` reports tree, title override, tab color,
/// and link changes; this object also watches every surface's working
/// directory. Bursts of changes (such as dragging a split divider) are
/// coalesced into one `ProjectStore.syncFromTab` call.
@MainActor
final class ProjectTabSync {
    private static let delay: DispatchTimeInterval = .milliseconds(300)

    private weak var controller: TerminalController?
    private var pwdCancellables: Set<AnyCancellable> = []
    private var pending: DispatchWorkItem?

    init(controller: TerminalController) {
        self.controller = controller
    }

    /// The surface tree or the project link changed: re-watch every
    /// surface's working directory and schedule a sync.
    func refresh() {
        pwdCancellables.removeAll()
        guard let controller else { return }
        for surface in controller.surfaceTree {
            surface.$pwd
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] _ in self?.schedule() }
                .store(in: &pwdCancellables)
        }
        schedule()
    }

    /// Request a sync after the current burst of changes settles.
    func schedule() {
        pending?.cancel()
        guard controller?.projectId != nil else {
            pending = nil
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: work)
    }

    /// Run a pending sync now, if any.
    func flush() {
        guard let work = pending else { return }
        work.cancel()
        pending = nil
        guard let controller else { return }
        ProjectStore.shared.syncFromTab(controller: controller)
    }
}
