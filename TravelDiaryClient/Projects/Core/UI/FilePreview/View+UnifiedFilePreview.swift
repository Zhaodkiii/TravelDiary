import SwiftUI

// MARK: - View 扩展
/// 为 SwiftUI View 扩展统一文件预览弹窗功能
extension View {
    
    /// 统一文件预览的数组版便捷弹窗方法（封装 sheet 弹窗）
    /// - Parameters:
    ///   - isPresented: 控制弹窗显示/隐藏的绑定
    ///   - inputs: 预览文件数组
    ///   - startIndex: 列表中的起始预览位置，默认从第一张开始
    ///   - onDismiss: 弹窗关闭时的可选回调
    /// - Returns: 包装后的 View
    func unifiedFilePreview(
        isPresented: Binding<Bool>,
        inputs: [FilePreviewInput],
        startIndex: Int = 0,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            UnifiedFilePreview(inputs: inputs, startIndex: startIndex) {
                isPresented.wrappedValue = false
            }
        }
    }

}
