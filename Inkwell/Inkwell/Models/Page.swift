import Foundation
import SwiftData

/// A single page inside a notebook. Holds the PencilKit drawing as raw data
/// plus a lightweight set of typed text boxes, so both handwriting and typed
/// notes can live on the same page.
@Model
final class Page {
    var index: Int
    var drawingData: Data
    var templateRawValue: String
    var textBoxesData: Data
    var createdAt: Date
    var updatedAt: Date

    var notebook: Notebook?

    var template: PageTemplate {
        get { PageTemplate(rawValue: templateRawValue) ?? .blank }
        set { templateRawValue = newValue.rawValue }
    }

    var textBoxes: [TextBox] {
        get {
            (try? JSONDecoder().decode([TextBox].self, from: textBoxesData)) ?? []
        }
        set {
            textBoxesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    init(index: Int, template: PageTemplate = .blank, notebook: Notebook? = nil) {
        self.index = index
        self.drawingData = Data()
        self.templateRawValue = template.rawValue
        self.textBoxesData = Data()
        self.notebook = notebook
        self.createdAt = .now
        self.updatedAt = .now
    }
}
