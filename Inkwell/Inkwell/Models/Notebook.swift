import Foundation
import SwiftData

/// A notebook is a collection of pages that share a default paper template
/// and a cover color, similar to a Notability "subject" notebook.
@Model
final class Notebook {
    var title: String
    var defaultTemplateRawValue: String
    var coverColorName: String
    var createdAt: Date
    var updatedAt: Date

    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Page.notebook)
    var pages: [Page] = []

    var defaultTemplate: PageTemplate {
        get { PageTemplate(rawValue: defaultTemplateRawValue) ?? .blank }
        set { defaultTemplateRawValue = newValue.rawValue }
    }

    init(
        title: String,
        template: PageTemplate = .blank,
        coverColorName: String = ColorPalette.yellow.rawValue,
        folder: Folder? = nil
    ) {
        self.title = title
        self.defaultTemplateRawValue = template.rawValue
        self.coverColorName = coverColorName
        self.folder = folder
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Pages sorted for display; call after mutating `pages` if needed elsewhere.
    var sortedPages: [Page] {
        pages.sorted { $0.index < $1.index }
    }
}
