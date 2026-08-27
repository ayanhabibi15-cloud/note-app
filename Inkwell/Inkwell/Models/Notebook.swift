import Foundation
import SwiftData

/// A notebook is a collection of pages that share a default paper template
/// and a cover color, similar to a Notability "subject" notebook.
@Model
final class Notebook {
    var title: String
    var defaultTemplateRawValue: String
    var coverColorName: String
    var areaRawValue: String
    var createdAt: Date
    var updatedAt: Date

    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Page.notebook)
    var pages: [Page] = []

    /// Tasks that point at this notebook ("study chapter 4"). Nullified rather
    /// than cascaded: deleting a notebook shouldn't silently delete to-dos.
    @Relationship(deleteRule: .nullify, inverse: \TaskItem.notebook)
    var linkedTasks: [TaskItem] = []

    var area: LifeArea {
        get { LifeArea.from(areaRawValue) }
        set { areaRawValue = newValue.rawValue }
    }

    var defaultTemplate: PageTemplate {
        get { PageTemplate(rawValue: defaultTemplateRawValue) ?? .blank }
        set { defaultTemplateRawValue = newValue.rawValue }
    }

    init(
        title: String,
        template: PageTemplate = .blank,
        coverColorName: String = ColorPalette.yellow.rawValue,
        area: LifeArea = .school,
        folder: Folder? = nil
    ) {
        self.title = title
        self.defaultTemplateRawValue = template.rawValue
        self.coverColorName = coverColorName
        self.areaRawValue = area.rawValue
        self.folder = folder
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Pages sorted for display; call after mutating `pages` if needed elsewhere.
    var sortedPages: [Page] {
        pages.sorted { $0.index < $1.index }
    }
}
