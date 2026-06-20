import SwiftUI

struct ReaderView: View {
    let content: ChapterContent

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text(content.title)
                    .font(.title.bold())
                    .padding(.bottom, 12)

                ForEach(Array(content.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
        .background(Color(red: 0.96, green: 0.93, blue: 0.86).ignoresSafeArea())
        .navigationTitle(content.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

