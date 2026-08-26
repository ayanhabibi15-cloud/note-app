import Foundation
import SwiftData

/// A user-created folder. Folders can nest arbitrarily deep and hold
/// notebooks, so people can organize however suits them (by class, by
/// project, by year) rather than a fixed structure.
@Model
final class Folder {
    var name: String
    var symbolName: String
    var colorName: String
    var createdAt: Date
    var sortOrder: Int

    var parent: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Folder.parent)
    var subfolders: [Folder] = []

    @Relationship(deleteRule: .cascade, inverse: \Notebook.folder)
    var notebooks: [Notebook] = []

    init(
        name: String,
        symbolName: String = "folder.fill",
        colorName: String = ColorPalette.blue.rawValue,
        parent: Folder? = nil,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.symbolName = symbolName
        self.colorName = colorName
        self.parent = parent
        self.sortOrder = sortOrder
        self.createdAt = .now
    }
}
