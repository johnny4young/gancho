import GanchoDesign
import GanchoKit
import SwiftUI

/// A colour clip's hero: the swatch, its four formats with copy, and how it
/// reads as text on white and on the dark panel surface.
struct PeekColorHero: View {
    let color: ColorValue
    let copy: (_ value: String, _ label: String) -> Void

    /// The dark panel surface the second card measures against.
    static let darkSurface = ColorValue(red: 0x1C, green: 0x1C, blue: 0x1E)
    static let white = ColorValue(red: 255, green: 255, blue: 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            swatch
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
                formatRow("HEX", key: "hex", value: color.hex)
                formatRow("RGB", key: "rgb", value: color.rgb)
                formatRow("HSL", key: "hsl", value: color.hsl)
                formatRow("Swift", key: "swift", value: color.swift)
                HStack(spacing: 6) {
                    contrastCard(on: Self.white, title: "on white", id: "light")
                        .environment(\.colorScheme, .light)
                    contrastCard(
                        on: Self.darkSurface, title: "on \(Self.darkSurface.hex)", id: "dark"
                    )
                    .environment(\.colorScheme, .dark)
                }
                .padding(.top, 6)
            }
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 10, trailing: 12))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-color-hero")
    }

    private var swatch: some View {
        Rectangle()
            .fill(Color(Color.Resolved(color)))
            .frame(height: 74)
            .overlay(alignment: .bottomLeading) {
                Text(verbatim: color.hex)
                    .panelFont(size: 13, .bold, design: .monospaced)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                    .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: GanchoTokens.Radius.md,
                    topTrailingRadius: GanchoTokens.Radius.md, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private func formatRow(_ label: String, key: String, value: String) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Text(verbatim: label)
                .panelFont(size: 10, .bold)
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
            Text(verbatim: value)
                .panelFont(.caption, design: .monospaced)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            IconActionButton(
                "Copy \(label)", systemImage: "doc.on.doc", identifier: "peek-color-copy-\(key)"
            ) {
                copy(value, label)
            }
            .foregroundStyle(.secondary)
        }
        .frame(minHeight: 26)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-color-format-\(key)")
    }

    /// The clip colour set as text on `background`, its ratio and its grade.
    private func contrastCard(
        on background: ColorValue, title: LocalizedStringKey, id: String
    )
        -> some View
    {
        let ratio = Contrast.ratio(Color.Resolved(color), Color.Resolved(background))
        return HStack(spacing: GanchoTokens.Spacing.xs) {
            Text(verbatim: "Aa")
                .panelFont(size: 11, .heavy)
                .foregroundStyle(Color(Color.Resolved(color)))
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).foregroundStyle(.secondary)
                Text(verbatim: Contrast.label(ratio)).monospacedDigit()
            }
            .panelFont(size: 11)
            Spacer(minLength: 0)
            gradeTag(Contrast.grade(ratio))
        }
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            Color(Color.Resolved(background)),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("peek-color-contrast-\(id)")
    }

    private func gradeTag(_ grade: Contrast.Grade) -> some View {
        let (title, tint): (LocalizedStringKey, Color) =
            switch grade {
            case .aa: ("AA", GanchoTokens.Palette.success)
            case .aaLarge: ("AA Large", GanchoTokens.Palette.warning)
            case .belowAA: ("below AA", GanchoTokens.Palette.danger)
            }
        return Text(title)
            .panelFont(size: 11, .bold)
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .frame(height: 20)
            .ganchoTintedPill(tint, wash: 0.14)
            .fixedSize()
    }
}
