import Foundation

enum SecondCameraEditorL10n {
    nonisolated static func tr(_ key: String, fallback: String) -> String {
        NSLocalizedString(
            key,
            tableName: "SecondCamera",
            bundle: .main,
            value: fallback,
            comment: ""
        )
    }

    enum Home {
        nonisolated static var title: String { tr("second_camera.home.title", fallback: "相机") }
        nonisolated static var open: String { tr("second_camera.home.open", fallback: "打开相机") }
        nonisolated static var subtitle: String {
            tr(
                "second_camera.home.subtitle",
                fallback: "基于 Camera-main / SparkClient CustomCamera 封装，支持照片与视频拍摄。"
            )
        }
        nonisolated static var tabTitle: String { tr("second_camera.tab.title", fallback: "相机") }
    }

    enum Preview {
        nonisolated static var back: String { tr("second_camera.preview.back", fallback: "返回") }
        nonisolated static var done: String { tr("second_camera.preview.done", fallback: "完成") }
        nonisolated static var save: String { tr("second_camera.preview.save", fallback: "保存") }
        nonisolated static var saved: String { tr("second_camera.preview.saved", fallback: "已保存到相册") }
        nonisolated static var saveFailed: String { tr("second_camera.preview.save_failed", fallback: "保存失败") }
    }

    enum PublicPreview {
        nonisolated static var close: String { tr("second_camera.public_preview.close", fallback: "关闭") }
        nonisolated static var imageLoadFailed: String {
            tr("second_camera.public_preview.image_load_failed", fallback: "图片无法加载")
        }
        nonisolated static var empty: String {
            tr("second_camera.public_preview.empty", fallback: "没有可预览的图片")
        }
        nonisolated static var fileMissing: String {
            tr("second_camera.public_preview.file_missing", fallback: "文件已失效")
        }
        nonisolated static var thumbnailFallback: String {
            tr("second_camera.multi.thumbnail_fallback", fallback: "预览缩略图")
        }

        nonisolated static func thumbnailAccessibility(index: Int, total: Int) -> String {
            String(
                format: tr("second_camera.public_preview.thumbnail_a11y", fallback: "第 %d 张，共 %d 张"),
                locale: Locale.current,
                index,
                total
            )
        }
    }

    enum Editor {
        nonisolated static var draw: String { tr("second_camera.editor.draw", fallback: "画笔") }
        nonisolated static var crop: String { tr("second_camera.editor.crop", fallback: "裁剪") }
        nonisolated static var cancel: String { tr("second_camera.editor.cancel", fallback: "取消") }
        nonisolated static var confirm: String { tr("second_camera.editor.confirm", fallback: "确认") }
        nonisolated static var discardChangesTitle: String { tr("second_camera.editor.discard_changes_title", fallback: "放弃更改？") }
        nonisolated static var discardChangesMessage: String { tr("second_camera.editor.discard_changes_message", fallback: "当前编辑内容不会保存。") }
        nonisolated static var discard: String { tr("second_camera.editor.discard", fallback: "放弃") }
        nonisolated static var sticker: String { tr("second_camera.sticker.title", fallback: "贴纸") }
    }

    enum Quality {
        nonisolated static var title: String { tr("second_camera.quality.title", fallback: "图片质量") }
        nonisolated static var original: String { tr("second_camera.quality.original", fallback: "原图") }
        nonisolated static var high: String { tr("second_camera.quality.high", fallback: "高清") }
        nonisolated static var standard: String { tr("second_camera.quality.standard", fallback: "标准") }
        nonisolated static var compressed: String { tr("second_camera.quality.compressed", fallback: "压缩") }
    }

    enum Error {
        nonisolated static var noMedia: String { tr("second_camera.error.no_media", fallback: "没有可用的媒体内容") }
        nonisolated static var loadFailed: String { tr("second_camera.error.load_failed", fallback: "无法读取媒体内容") }
        nonisolated static var editorInitFailed: String { tr("second_camera.error.editor_init_failed", fallback: "无法初始化图片编辑器") }
        nonisolated static var editorGeneric: String { tr("second_camera.error.editor_generic", fallback: "编辑错误") }
        nonisolated static var noImageToSave: String { tr("second_camera.error.no_image_to_save", fallback: "没有可保存的图片") }
        nonisolated static var ok: String { tr("second_camera.error.ok", fallback: "好") }
    }

    enum Multi {
        nonisolated static var addMore: String { tr("second_camera.multi.add_more", fallback: "添加") }
        nonisolated static var continueCapture: String { tr("second_camera.multi.continue_capture", fallback: "继续拍摄") }
        nonisolated static var pickFromLibrary: String { tr("second_camera.multi.pick_from_library", fallback: "从相册选择") }
        nonisolated static var delete: String { tr("second_camera.multi.delete", fallback: "删除") }
        nonisolated static var deleteConfirmTitle: String { tr("second_camera.multi.delete_confirm_title", fallback: "删除这张照片？") }
        nonisolated static var deleteConfirmMessage: String { tr("second_camera.multi.delete_confirm_message", fallback: "删除后无法在本次预览中恢复。") }
        nonisolated static var deleteConfirmAction: String { tr("second_camera.multi.delete_confirm_action", fallback: "删除") }
        nonisolated static var maxCountMessage: String { tr("second_camera.multi.max_count_message", fallback: "最多可选择 %d 张") }
        nonisolated static var processingProgress: String { tr("second_camera.multi.processing_progress", fallback: "正在处理 %d/%d") }
        nonisolated static var deleteLastTitle: String { tr("second_camera.multi.delete_last_title", fallback: "删除最后一张？") }
        nonisolated static var deleteLastMessage: String { tr("second_camera.multi.delete_last_message", fallback: "删除后将返回相机。") }
        nonisolated static var discardAllTitle: String { tr("second_camera.multi.discard_all_title", fallback: "放弃所有照片？") }
        nonisolated static var discardAllMessage: String { tr("second_camera.multi.discard_all_message", fallback: "已拍摄的照片不会保存。") }
        nonisolated static var discardAction: String { tr("second_camera.multi.discard_action", fallback: "放弃") }
    }
}
