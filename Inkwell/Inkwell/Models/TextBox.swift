import Foundation

/// A single movable, resizable text annotation on a page. Pages store an
/// array of these (as JSON) alongside the PencilKit drawing, mirroring
/// Notability's separate "type tool" layer.
struct TextBox: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String
    var x: Double
    var y: Double
    var width: Double = 220
    var fontSize: Double = 17
    var colorHex: String = "#000000"
}
