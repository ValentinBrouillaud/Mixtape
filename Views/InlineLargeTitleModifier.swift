//
//  InlineLargeTitleModifier.swift
//  Mixtape
//
//  Inline large navigation title that fades out on scroll (iOS).
//


#if os(iOS)
import SwiftUI

@available(iOS 17.0, *)
struct InlineLargeTitleModifier<TrailingContent: View>: ViewModifier {
    let title: LocalizedStringKey
    let trailingContent: TrailingContent
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
            .toolbar { headerToolbar }
            .toolbarBackground(MixtapePalette.background(scheme), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 12) {
            trailingContent
            Text(title).font(.system(size: 24, weight: .bold)).lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 4)
    }

    @ToolbarContentBuilder
    private var headerToolbar: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { header }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { header }
        }
    }

}

@available(iOS 17.0, *)
extension View {
    func inlineLargeTitle<TrailingContent: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder trailing: () -> TrailingContent
    ) -> some View {
        modifier(InlineLargeTitleModifier(
            title: title,
            trailingContent: trailing()
        ))
    }

    func inlineLargeTitle(_ title: LocalizedStringKey) -> some View {
        modifier(InlineLargeTitleModifier(
            title: title,
            trailingContent: Spacer()
        ))
    }
}
#endif
