import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drop Position Types

enum DropEdge: Equatable {
    case top
    case bottom
}

struct ProjectDropTarget: Equatable {
    let projectID: UUID
    let edge: DropEdge
}

/// Identifies the item currently being dragged in the sidebar. Drag sources
/// are mutually exclusive — only one is ever in flight.
enum SidebarDragSource: Equatable {
    case project(UUID)
    case folder(UUID)
    case tab(ObjectIdentifier)
}

// MARK: - ProjectsDragState

/// Shared drag/drop state for the entire sidebar (tabs and projects sections).
///
/// After a drop, callers must call `reset()` synchronously. Any stray
/// `dropEntered`/`dropUpdated` callbacks SwiftUI dispatches afterward see
/// `isDragging == false` and short-circuit, so drop indicators don't stick.
///
/// Mutators guard against equal-value writes — `@Published` fires
/// `objectWillChange` in `willSet` even when the new value is identical,
/// so an unconditional `nil = nil` would still invalidate every observer.
final class ProjectsDragState: ObservableObject {
    @Published private(set) var draggingItem: SidebarDragSource?
    /// Project under the cursor. Coexists with `dropTargetFolderID` because
    /// hovering a project nested in a folder fires both delegates.
    @Published private(set) var projectDropTarget: ProjectDropTarget?
    @Published private(set) var dropTargetFolderID: UUID?
    @Published private(set) var dropTargetTabID: ObjectIdentifier?

    var isDragging: Bool { draggingItem != nil }

    func beginProjectDrag(_ id: UUID) { setDragging(.project(id)) }
    func beginFolderDrag(_ id: UUID) { setDragging(.folder(id)) }
    func beginTabDrag(_ id: ObjectIdentifier) { setDragging(.tab(id)) }

    private func setDragging(_ source: SidebarDragSource?) {
        if draggingItem != source { draggingItem = source }
    }

    func setProjectDropTarget(_ target: ProjectDropTarget?) {
        if projectDropTarget != target { projectDropTarget = target }
    }

    func setDropTargetFolderID(_ id: UUID?) {
        if dropTargetFolderID != id { dropTargetFolderID = id }
    }

    func setDropTargetTabID(_ id: ObjectIdentifier?) {
        if dropTargetTabID != id { dropTargetTabID = id }
    }

    func reset() {
        setDragging(nil)
        setProjectDropTarget(nil)
        setDropTargetFolderID(nil)
        setDropTargetTabID(nil)
    }
}

extension ProjectsDragState {
    /// UUID accessors for `sidebarDropIndicator`, which takes `UUID?` rather
    /// than the drag-source enum.
    var draggingProjectUUID: UUID? {
        if case .project(let id) = draggingItem { return id }
        return nil
    }

    var draggingFolderUUID: UUID? {
        if case .folder(let id) = draggingItem { return id }
        return nil
    }
}

// MARK: - SidebarDropPayload

/// Typed representation of sidebar drag payloads. The private
/// `com.mitchellh.ghosttySidebarItem` UTI gates `hasItemsConforming(to:)`
/// so external text/file drags (Safari URLs, Finder files) never reach
/// the in-app delegates.
enum SidebarDropPayload: Codable, Transferable {
    case project(UUID)
    case folder(UUID)
    case tab(Int)

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .ghosttySidebarItem)
    }

    /// Wraps the payload in a freshly registered `NSItemProvider` for
    /// returning from `.onDrag { ... }`.
    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.register(self)
        return provider
    }
}

extension UTType {
    /// A private format identifying a drag originating from the Ghostty
    /// sidebar. Registered in `Ghostty-Info.plist` under
    /// `UTExportedTypeDeclarations`.
    static let ghosttySidebarItem = UTType(exportedAs: "com.mitchellh.ghosttySidebarItem")
}

// MARK: - DropInfo helper

extension DropInfo {
    /// Loads the first `SidebarDropPayload` from the drop and delivers it
    /// to `handler` on the main actor. Returns `false` if no item provider
    /// is available.
    func loadSidebarPayload(_ handler: @escaping @MainActor @Sendable (SidebarDropPayload) -> Void) -> Bool {
        guard let provider = itemProviders(for: [.ghosttySidebarItem]).first else { return false }
        _ = provider.loadTransferable(type: SidebarDropPayload.self) { result in
            guard case .success(let payload) = result else { return }
            Task { @MainActor in handler(payload) }
        }
        return true
    }
}
