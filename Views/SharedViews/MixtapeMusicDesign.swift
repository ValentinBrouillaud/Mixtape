import SwiftUI

enum MixtapeMainTab: String, CaseIterable, Identifiable {
    case home, discovery, library, search
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self { case .home: "Home"; case .discovery: "Discovery"; case .library: "Library"; case .search: "Search" }
    }
    func icon(selected: Bool) -> String {
        switch self {
        case .home: selected ? "house.fill" : "house"
        case .discovery: selected ? "safari.fill" : "safari"
        case .library: selected ? "square.stack.fill" : "square.stack"
        case .search: "magnifyingglass"
        }
    }
}

struct MixtapeRecentTile<Artwork: View>: View {
    let title: String
    let onPlay: () -> Void
    @ViewBuilder var artwork: () -> Artwork

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 8) {
                artwork().frame(width: 52, height: 52).clipped()
                Text(title).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 8)
            }
            .mixtapeCard()
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}

struct MixtapeBottomNavigation: View {
    @Environment(\.colorScheme) private var scheme
    let selected: MixtapeMainTab
    let onSelect: (MixtapeMainTab) -> Void
    var body: some View {
        HStack(spacing: 0) {
            ForEach(MixtapeMainTab.allCases) { tab in
                Button { onSelect(tab) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon(selected: tab == selected))
                            .font(.system(size: 21, weight: tab == selected ? .semibold : .regular))
                        Text(tab.title).font(.system(size: 10, weight: tab == selected ? .semibold : .medium))
                    }
                    .foregroundStyle(tab == selected ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .background(MixtapePalette.background(scheme))
    }
}

/// The mini-player's actual layout, with callbacks supplied by the player view.
/// Keeping presentation independent makes light/dark layout previews possible.
struct MixtapeMiniPlayerLayout<Artwork: View>: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let artist: String
    let isPlaying: Bool
    let fraction: Double
    let onOpen: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    var onError: (() -> Void)? = nil
    var onOpenWeb: (() -> Void)? = nil
    @ViewBuilder var artwork: () -> Artwork

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onOpen) {
                    HStack(spacing: 10) {
                        artwork().frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                            Text(artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                if let onError {
                    Button(action: onError) { Image(systemName: "exclamationmark.circle").foregroundStyle(MixtapePalette.accent) }
                        .accessibilityLabel("Diagnostic audio")
                }
                if let onOpenWeb {
                    Button(action: onOpenWeb) { Image(systemName: "globe").font(.system(size: 18)) }
                        .accessibilityLabel("Afficher YouTube Music")
                }
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 21, weight: .semibold)).frame(width: 38, height: 44)
                }
                .accessibilityLabel(Text(isPlaying ? "Pause" : "Play", tableName: "MixtapeTheme"))
                Button(action: onNext) {
                    Image(systemName: "forward.end.fill").font(.system(size: 17)).frame(width: 32, height: 44)
                }.accessibilityLabel("Next")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 7)
            GeometryReader { proxy in
                Capsule().fill(Color.primary.opacity(0.12)).overlay(alignment: .leading) {
                    Capsule().fill(MixtapePalette.accent)
                        .frame(width: proxy.size.width * min(1, max(0, fraction.isFinite ? fraction : 0)))
                }
            }
            .frame(height: 2).padding(.horizontal, 10)
            .padding(.bottom, 2).accessibilityHidden(true)
        }
        .background(MixtapePalette.raised(scheme), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct MixtapeFullPlayerLayout<Artwork: View, Info: View, Progress: View, Controls: View, Actions: View, Panel: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    let sourceTitle: String
    let showsPanel: Bool
    let onDismiss: () -> Void
    @ViewBuilder var artwork: () -> Artwork
    @ViewBuilder var info: () -> Info
    @ViewBuilder var progress: () -> Progress
    @ViewBuilder var controls: () -> Controls
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var panel: () -> Panel

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 700
            let size = max(120, min(min(proxy.size.width, 520) - 48, proxy.size.height - (compact ? 386 : 446)))
            Group {
                if typeSize.isAccessibilitySize || proxy.size.height < 530 {
                    ScrollView { content(size: size, compact: compact) }
                } else {
                    content(size: size, compact: compact)
                }
            }
            .frame(maxWidth: 520, maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            MixtapePalette.background(scheme)
            LinearGradient(colors: [MixtapePalette.accent.opacity(scheme == .dark ? 0.10 : 0.05), .clear],
                startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeInOut(duration: 0.2), value: showsPanel)
    }

    private func content(size: CGFloat, compact: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.down").font(.system(size: 18, weight: .semibold)).frame(width: 40, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Close")
                Spacer(minLength: 4)
                VStack(spacing: 2) {
                    Text("Now playing", tableName: "MixtapeTheme").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    Text(sourceTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Color.clear.frame(width: 40, height: 44).accessibilityHidden(true)
            }
            if showsPanel {
                HStack(spacing: 12) {
                    artwork().frame(width: 48, height: 48).clipped()
                    info()
                }.padding(.top, 8)
                panel().frame(maxHeight: .infinity).padding(.top, 12)
            } else {
                artwork().frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.12), radius: 18, y: 8)
                    .padding(.top, compact ? 8 : 16)
                info().padding(.top, compact ? 12 : 20)
            }
            progress().padding(.top, compact ? 8 : 16)
            controls().frame(height: compact ? 56 : 64).padding(.top, compact ? 12 : 20)
            actions().frame(height: 44).padding(.top, compact ? 12 : 20)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, compact ? 8 : 12)
    }
}

private struct MixtapeScreenStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(MixtapePalette.background(scheme))
            .tint(MixtapePalette.accent)
            #if os(iOS)
            .toolbarBackground(MixtapePalette.background(scheme), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
    }
}

extension View {
    func mixtapeScreenStyle() -> some View { modifier(MixtapeScreenStyle()) }
    func mixtapeCard() -> some View { modifier(MixtapeCardStyle()) }
}

private struct MixtapeCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.background(MixtapePalette.surface(scheme), in: RoundedRectangle(cornerRadius: 8))
    }
}
