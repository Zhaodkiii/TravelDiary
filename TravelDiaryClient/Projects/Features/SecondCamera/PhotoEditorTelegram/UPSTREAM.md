# Telegram iOS photo editor source snapshot

The `UpstreamTelegram` directory is a direct source snapshot from the local
`参考包/Telegram-iOS` checkout. It is intentionally excluded from the
TravelDiary application target because the original files import Telegram's
private build modules (`Display`, `ComponentFlow`, `TelegramCore`,
`AccountContext`, `SwiftSignalKit`, and others).

## Included upstream editing code

- `MediaEditor`: Metal/Core Image render passes, editor values, render chain,
  blur, enhancement, sharpen, histogram, sticker outline, and drawing models.
- `MediaEditorScreen`: adjustment, curves, tint, blur, crop, selection,
  cutout, and media-tool UI source.
- `DrawingUI`: gesture pipeline, pen/neon tools, drawing canvas, text/sticker/
  shape entities, snapping, eyedropper, and tool controls.
- Telegram editor Metal shader source used by the photo pipeline.

## Intentionally removed from the snapshot

- Camera and recording code.
- Video decode/export, FFmpeg writers, audio tracks, scrubber and cover editor.
- Story upload, chat sending, drafts, account context and Telegram navigation.
- Location, weather, link and reaction entities that require Telegram services.

## Compiled source port

The active editor is the local package at
`Packages/TelegramPhotoEditorKit`. Its adjustment, tint, blur, curves and crop
UI files, Metal render passes and Metal shaders are copied from this Telegram
checkout. Small compatibility targets replace private Telegram infrastructure
such as `Display`, `ComponentFlow`, `SliderComponent` and presentation strings.

The Swift files next to this document are the earlier independent prototype.
They are retained temporarily as migration reference, but the photo picker now
opens `TelegramPhotoEditorViewController` from the local package.

Upstream repository: `https://github.com/TelegramMessenger/Telegram-iOS.git`
Snapshot commit: `6ad963e5b62d354da79040f388ae2b9132fb17b8`
