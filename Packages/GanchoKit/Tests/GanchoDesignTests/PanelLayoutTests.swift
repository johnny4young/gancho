import Testing

@testable import GanchoDesign

@Suite("PanelLayout — list by default, gallery columns by width")
struct PanelLayoutTests {
    @Test("Unknown or missing values resolve to the list")
    func resolution() {
        #expect(PanelLayout.resolved(nil) == .list)
        #expect(PanelLayout.resolved("mosaic") == .list)
        #expect(PanelLayout.resolved("gallery") == .gallery)
        #expect(PanelLayout.list.toggled == .gallery)
        #expect(PanelLayout.gallery.toggled == .list)
    }

    @Test("Columns follow the width and never drop below two")
    func columns() {
        #expect(PanelLayout.galleryColumns(forWidth: 200) == 2)
        #expect(PanelLayout.galleryColumns(forWidth: 360) == 2)
        #expect(PanelLayout.galleryColumns(forWidth: 520) == 3)
        #expect(PanelLayout.galleryColumns(forWidth: 900) == 5)
    }
}
