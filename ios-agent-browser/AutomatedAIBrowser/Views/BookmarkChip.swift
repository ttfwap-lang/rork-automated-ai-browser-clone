import SwiftUI

/// One checkpoint thumbnail in the strip.
struct BookmarkChip: View {
    let bookmark: PageBookmark
    let isCurrent: Bool
    let isTappable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topLeading) {
                Color(Theme.surface)
                    .frame(width: 62, height: 84)
                    .overlay {
                        if let thumbnail = bookmark.thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .allowsHitTesting(false)
                        } else {
                            Image(systemName: "doc.text")
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isCurrent ? Theme.cyan : Theme.line, lineWidth: isCurrent ? 1.5 : 1)
                    )

                Text("\(bookmark.number)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(isCurrent ? Theme.cyan : Theme.textSecondary, in: Capsule())
                    .padding(4)
            }

            Text(bookmark.label)
                .font(.system(size: 9))
                .foregroundStyle(isCurrent ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 62, alignment: .leading)
        }
        .opacity(isTappable ? 1 : 0.75)
    }
}
