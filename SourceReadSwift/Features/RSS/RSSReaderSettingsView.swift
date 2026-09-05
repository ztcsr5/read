import SwiftUI

/// RSS uses the same typography and automation values as the chapter reader,
/// but presents only controls that make sense for a single article.  Sharing
/// the numeric editor prevents slider/text-field drift between reader types.
struct RSSReaderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var fontSize: Double
    @Binding var lineSpacing: Double
    @Binding var letterSpacing: Double
    @Binding var paragraphSpacing: Double
    @Binding var pagePadding: Double
    @Binding var titleSpacing: Double
    @Binding var ttsRate: Double
    @Binding var autoScrollDelay: Double
    @Binding var backgroundRawValue: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("外观")
                        .font(.headline)
                    HStack(spacing: 12) {
                        ForEach(ReaderBackground.allCases) { item in
                            Button {
                                backgroundRawValue = item.rawValue
                            } label: {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 42, height: 42)
                                    .overlay {
                                        Circle().stroke(
                                            backgroundRawValue == item.rawValue ? AppTheme.accent : Color.secondary.opacity(0.25),
                                            lineWidth: backgroundRawValue == item.rawValue ? 3 : 1
                                        )
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.title)
                        }
                    }

                    Text("排版")
                        .font(.headline)
                        .padding(.top, 4)
                    readerSlider("字号", value: $fontSize, range: 14...32, step: 1, unit: "pt", help: "正文文字大小")
                    readerSlider("行高", value: $lineSpacing, range: 2...18, step: 1, unit: "pt", help: "每行文字之间的垂直间距")
                    readerSlider("字距", value: $letterSpacing, range: 0...4, step: 0.2, unit: "pt", help: "字符之间的水平间距")
                    readerSlider("段距", value: $paragraphSpacing, range: 8...32, step: 1, unit: "pt", help: "相邻段落之间的留白")
                    readerSlider("左右间距", value: $pagePadding, range: 14...40, step: 1, unit: "pt", help: "正文距离屏幕边缘的距离")
                    readerSlider("标题间距", value: $titleSpacing, range: 0...36, step: 2, unit: "pt", help: "标题与正文之间的留白")

                    Text("阅读辅助")
                        .font(.headline)
                        .padding(.top, 4)
                    readerSlider("朗读速度", value: $ttsRate, range: 0.35...0.65, step: 0.01, unit: "倍速", help: "从当前可见段落开始朗读")
                    readerSlider("自动滚动间隔", value: $autoScrollDelay, range: 0.25...30, step: 0.25, unit: "秒", help: "每次推进到下一段前等待的时间")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .padding(.bottom, 24)
            }
            .pageBackground()
            .navigationTitle("文章阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func readerSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                ReaderNumberInput(title: title, value: value, range: range, step: step, unit: unit)
            }
            Slider(value: value, in: range, step: step)
            Text(help).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
