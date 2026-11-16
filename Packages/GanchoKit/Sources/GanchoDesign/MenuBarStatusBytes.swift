/// sRGB bytes of the status hues and neutral inks, shared by the palette and the menu-bar
/// glyph. The menu-bar helper compiles this file without the rest of the
/// module, so its name keeps it inside the helper's CI path filter.
enum StatusBytes {
    static let ink = (0x12, 0x14, 0x13)
    static let ink3 = (0x62, 0x66, 0x64)
    static let dangerLight = (0xC5, 0x30, 0x1C)
    static let dangerDark = (0xFF, 0x70, 0x62)
    static let warning = (0xFF, 0x9F, 0x0A)
    static let indigo = (0x5E, 0x5C, 0xE6)
    static let agentLight = (0x2F, 0x7D, 0xE1)
    static let agentDark = (0x5A, 0xC8, 0xFA)
}
