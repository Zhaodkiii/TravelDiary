import SwiftUI
import AVKit

struct DiaryExportVideoResultPage: View {
    let result: DiaryBookVideoExport
    let saved: Bool
    let saving: Bool
    let onSave: () -> Void
    @State private var player: AVPlayer?
    @State private var exportingFile = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: saved ? "checkmark.seal.fill" : "film").font(.system(size: 48)).foregroundStyle(.tint)
            Text(saved ? "翻页回忆，已收藏" : "翻页视频已生成").font(.title2.bold())
            VideoPlayer(player: player)
                .aspectRatio(result.size.width / result.size.height, contentMode: .fit)
                .frame(maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text("\(result.spreadCount) 个跨页 · \(Int(ceil(result.duration))) 秒 · \(Int(result.size.width)) × \(Int(result.size.height))\nMP4 · 30 帧/秒 · 无声")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if result.usedFallbackFonts {
                Text("部分字体暂不可用，已使用替代字体，文字排版可能变化。").font(.caption).foregroundStyle(.orange)
            }
            if saving { ProgressView("正在保存到相册…") }
            else if saved { Label("已保存到相册", systemImage: "checkmark").foregroundStyle(.secondary) }
            else { Button("保存到相册", action: onSave).buttonStyle(.borderedProminent) }
            ShareLink(item: result.url) { Label("分享视频", systemImage: "square.and.arrow.up") }
                .buttonStyle(.bordered).disabled(saving)
            Button("存储到文件", systemImage: "folder") { exportingFile = true }.disabled(saving)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .onAppear { player = AVPlayer(url: result.url) }
        .onDisappear { player?.pause(); player = nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active { player?.pause() } }
        .sheet(isPresented: $exportingFile) { DiaryVideoFilePicker(url: result.url) }
    }
}

private struct DiaryVideoFilePicker: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
}
