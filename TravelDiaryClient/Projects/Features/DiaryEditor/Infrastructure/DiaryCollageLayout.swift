import CoreGraphics

/// Preview and JPEG export share a portrait canvas and the same inset geometry.
enum DiaryCollageLayout {
    static let supportedCounts = [1, 2, 3, 4, 6]
    static let aspectRatio: CGFloat = 3.0 / 4.0

    static func frames(imageSizes: [CGSize], canvas: CGSize) -> [CGRect] {
        guard !imageSizes.isEmpty else { return [] }
        let count = imageSizes.count
        let columns = count >= 4 ? 2 : 1
        let rows = (count + columns - 1) / columns
        let widthFraction: CGFloat = count == 1 ? 0.88 : count == 2 ? 0.80 : count == 3 ? 0.52 : 0.42
        let cellWidth = canvas.width * widthFraction
        let gapX = canvas.width * 0.044
        let gapY = canvas.height * (count >= 4 ? 0.067 : 0.04)
        // Fit to each cell without cropping or distorting custom page proportions.
        let maxHeight = (canvas.height * 0.91 - gapY * CGFloat(rows - 1)) / CGFloat(rows)
        let cellHeight = min(maxHeight, imageSizes.map { cellWidth * $0.height / max(1, $0.width) }.max() ?? maxHeight)
        let groupHeight = cellHeight * CGFloat(rows) + gapY * CGFloat(rows - 1)
        return imageSizes.enumerated().map { index, size in
            let scale = min(cellWidth / max(1, size.width), cellHeight / max(1, size.height))
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            let row = index / columns
            let rowCount = min(columns, count - row * columns)
            let rowWidth = cellWidth * CGFloat(rowCount) + gapX * CGFloat(rowCount - 1)
            return CGRect(x: (canvas.width - rowWidth) / 2 + CGFloat(index % columns) * (cellWidth + gapX) + (cellWidth - fitted.width) / 2,
                          y: (canvas.height - groupHeight) / 2 + CGFloat(row) * (cellHeight + gapY) + (cellHeight - fitted.height) / 2,
                          width: fitted.width, height: fitted.height)
        }
    }
}
