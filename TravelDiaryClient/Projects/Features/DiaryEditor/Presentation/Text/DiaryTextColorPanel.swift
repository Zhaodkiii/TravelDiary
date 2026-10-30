import SwiftUI
import UIKit

/// Embedded in the text editor: no modal presentation, responder or independent copy of the draft.
struct DiaryTextColorPanel: View {
    let title: String
    @Binding var color: DiaryColor
    var supportsAlpha = false
    var onBegin: () -> Void = {}
    @State private var custom = false
    @State private var hue: Double = 0
    private let swatches: [(String, DiaryColor)] = [
        ("黑色", DiaryColor(red: 0, green: 0, blue: 0)), ("白色", .white), ("棕色", .brown),
        ("朱红", DiaryColor(red: 0.78, green: 0.12, blue: 0.1)),
        ("橙色", DiaryColor(red: 0.96, green: 0.42, blue: 0.16)), ("暖黄", .yellow),
        ("草绿", DiaryColor(red: 0.25, green: 0.47, blue: 0.32)),
        ("靛蓝", DiaryColor(red: 0.1, green: 0.27, blue: 0.55)),
        ("雾蓝", DiaryColor(red: 0.65, green: 0.8, blue: 0.88)),
        ("紫色", DiaryColor(red: 0.5, green: 0.3, blue: 0.67)), ("浅粉", .pink), ("纸白", .paper)
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                RoundedRectangle(cornerRadius: 7).fill(Color(uiColor: DiaryPageRenderer.color(color)))
                    .frame(width: 28, height: 28).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.secondary.opacity(0.4)))
                Text(hex).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(swatches.indices, id: \.self) { index in
                    let swatch = swatches[index]
                    Button {
                        onBegin()
                        var next = swatch.1
                        next.alpha = supportsAlpha ? color.alpha : 1
                        color = next
                        syncHue()
                    } label: {
                        RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: DiaryPageRenderer.color(swatch.1)))
                            .frame(height: 36)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.3)))
                            .overlay {
                                if matches(swatch.1) {
                                    Image(systemName: "checkmark").font(.caption.bold())
                                        .foregroundStyle(swatch.1.red + swatch.1.green + swatch.1.blue > 1.7 ? .black : .white)
                                }
                            }
                    }.buttonStyle(.plain).accessibilityLabel(swatch.0)
                        .accessibilityIdentifier("diary.text.swatch." + swatch.0)
                        .accessibilityAddTraits(matches(swatch.1) ? .isSelected : [])
                }
            }
            Button {
                onBegin(); syncHue(); custom.toggle()
            } label: {
                HStack { Text("自定义颜色"); Spacer(); Image(systemName: custom ? "chevron.up" : "chevron.down") }
                    .font(.subheadline).frame(minHeight: 36).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("diary.text.customColor")
            if custom {
                saturationBrightness
                HStack {
                    Text("色相").font(.caption).frame(width: 36, alignment: .leading)
                    Slider(value: Binding(get: { hue }, set: { value in
                        hue = value
                        let hsv = components
                        // Black/white have no useful hue; choosing a hue should produce a visible color.
                        write(hue: value, saturation: hsv.s < 0.01 ? 1 : hsv.s, brightness: hsv.v < 0.01 ? 1 : hsv.v)
                    }), in: 0...1, onEditingChanged: { editing in if editing { onBegin() } })
                        .tint(Color(hue: hue, saturation: 1, brightness: 1))
                        .accessibilityLabel(title + "色相")
                }
                channel("红", key: \.red, tint: .red)
                channel("绿", key: \.green, tint: .green)
                channel("蓝", key: \.blue, tint: .blue)
            }
            if supportsAlpha { channel("透明度", key: \.alpha, tint: .gray) }
            Text("选择即预览 · 点击上方 ✓ 保存全部文字修改")
                .font(.caption2).foregroundStyle(.secondary)
        }.onAppear(perform: syncHue)
    }
    private var hex: String {
        String(format: "#%02X%02X%02X", Int(color.red*255), Int(color.green*255), Int(color.blue*255))
    }
    private var components: (s: Double, v: Double) {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        DiaryPageRenderer.color(color).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return (Double(s), Double(v))
    }
    private func syncHue() {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        DiaryPageRenderer.color(color).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        if s > 0.01 && abs(hue - Double(h)) > 0.001 { hue = Double(h) }
    }
    private func matches(_ other: DiaryColor) -> Bool {
        abs(color.red-other.red) < 0.005 && abs(color.green-other.green) < 0.005 && abs(color.blue-other.blue) < 0.005
    }
    private func write(hue: Double, saturation: Double, brightness: Double) {
        let next = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: supportsAlpha ? color.alpha : 1)
        color = DiaryColor(Color(uiColor: next))
    }
    private var saturationBrightness: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(hue: hue, saturation: 1, brightness: 1))
                Rectangle().fill(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing))
                Rectangle().fill(LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(.white, lineWidth: 2).background(Circle().stroke(.black.opacity(0.5), lineWidth: 4))
                    .frame(width: 18, height: 18)
                    .position(x: max(9, min(geometry.size.width-9, CGFloat(components.s) * geometry.size.width)),
                              y: max(9, min(geometry.size.height-9, CGFloat(1-components.v) * geometry.size.height)))
            }.clipShape(RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    onBegin()
                    write(hue: hue, saturation: min(1, max(0, Double(value.location.x / max(1, geometry.size.width)))),
                          brightness: 1-min(1, max(0, Double(value.location.y / max(1, geometry.size.height)))))
                })
        }.frame(height: 120).accessibilityLabel(title + "饱和度和明度，或使用下方颜色滑块调整")
    }
    private func channel(_ label: String, key: WritableKeyPath<DiaryColor, Double>, tint: Color) -> some View {
        HStack {
            Text(label).font(.caption).frame(width: 42, alignment: .leading)
            Slider(value: Binding(get: { color[keyPath: key] }, set: { value in
                var next = color
                next[keyPath: key] = min(1, max(0, value))
                if !supportsAlpha { next.alpha = 1 }
                color = next
            }), in: 0...1, onEditingChanged: { editing in if editing { onBegin() } }).tint(tint).accessibilityLabel(title + label)
            Text("\(Int(color[keyPath: key]*255))").font(.caption.monospacedDigit()).frame(width: 30, alignment: .trailing)
        }
    }
}
