import Foundation
import CoreGraphics

/// Pure layout planning: no document mutations until every new photo fits.
nonisolated enum DiaryPhotoBatchLayout {
    struct Input {
        let photoSize: CGSize
        /// Includes the full sticker, decorations and its shadow, in photo-local coordinates.
        let bounds: CGRect
        var flippedHorizontally: Bool? = nil
        var flippedVertically: Bool? = nil
    }
    struct Placement {
        let transform: DiaryTransform
        let bounds: CGRect
    }

    static func plan(_ inputs: [Input], canvas: CGRect, region: CGRect? = nil,
                     obstacles: [CGRect] = [], foreground: [CGRect] = []) -> [Placement]? {
        guard !inputs.isEmpty, inputs.count <= 30, canvas.width > 0, canvas.height > 0 else { return nil }
        let safe = canvas.insetBy(dx: canvas.width * 0.05, dy: canvas.height * 0.05)
        let area = region.map { safe.intersection($0) } ?? safe
        guard !area.isNull, area.width > 0, area.height > 0 else { return nil }
        let gap = min(canvas.width, canvas.height) * 0.035
        let minimum = min(canvas.width, canvas.height) * 0.12
        if inputs.count <= 2, inputs.allSatisfy({ $0.photoSize.width >= $0.photoSize.height }),
           let compact = compactStack(inputs, area: area, canvas: canvas, gap: gap,
                                      obstacles: obstacles, foreground: foreground) { return compact }
        let slots = slots(inputs: inputs, area: area, gap: gap, minimum: minimum)
        guard slots.count == inputs.count else { return nil }
        // First remove the small offsets/angles; only then shrink the entire batch.
        for (factor, stagger) in [(1.0, true), (1.0, false), (0.95, false), (0.90, false), (0.85, false), (0.80, false), (0.75, false), (0.70, false), (0.65, false), (0.60, false), (0.55, false)] {
            var result = [Int: Placement]()
            var occupied = obstacles.filter {
                !$0.isNull && !$0.isEmpty && $0.insetBy(dx: -gap, dy: -gap).intersects(area)
            }
            let order = inputs.indices.sorted {
                let a = slots[$0], b = slots[$1]
                return a.width * a.height == b.width * b.height ? $0 < $1 : a.width * a.height > b.width * b.height
            }
            for index in order {
                let input = inputs[index], slot = slots[index]
                guard input.photoSize.width > 0, input.photoSize.height > 0,
                      input.bounds.width > 0, input.bounds.height > 0 else { return nil }
                let pivot = CGPoint(x: input.photoSize.width / 2, y: input.photoSize.height / 2)
                let angles: [CGFloat] = [-1.2, 0.8, -0.6, 1.4, -1, 0.5]
                let angle = stagger && inputs.count > 1 ? angles[index % angles.count] : 0
                var transform = DiaryTransform(position: .zero, pivot: pivot, rotationDegrees: angle,
                    flippedHorizontally: input.flippedHorizontally, flippedVertically: input.flippedVertically)
                let rotated = input.bounds.applying(transform.matrix)
                let scale = min(slot.width * 0.96 / rotated.width, slot.height * 0.96 / rotated.height) * factor
                guard scale >= 0.05, scale <= 20 else { continue }
                transform.scale = scale
                let local = input.bounds.applying(transform.matrix)
                // Minimum readable photo size, rather than just the decorative frame size.
                guard min(input.photoSize.width, input.photoSize.height) * scale >= minimum else { continue }
                let offset = stagger && inputs.count > 1 ? min(slot.width, slot.height) * 0.012 : 0
                let preferred = CGPoint(x: slot.midX + (index % 2 == 0 ? -offset : offset),
                                        y: slot.midY + (index % 3 == 0 ? offset : -offset))
                var centers = [preferred]
                // Obstacle-edge candidates find narrow free spaces a coarse grid can miss.
                let halfW = local.width / 2, halfH = local.height / 2
                let xEdges = [area.minX + halfW, area.maxX - halfW, preferred.x]
                    + occupied.flatMap { [$0.minX - gap - halfW, $0.maxX + gap + halfW] }
                let yEdges = [area.minY + halfH, area.maxY - halfH, preferred.y]
                    + occupied.flatMap { [$0.minY - gap - halfH, $0.maxY + gap + halfH] }
                let xs = Set(xEdges).sorted {
                    let a = abs($0 - preferred.x), b = abs($1 - preferred.x)
                    return a == b ? $0 < $1 : a < b
                }.prefix(12)
                let ys = Set(yEdges).sorted {
                    let a = abs($0 - preferred.y), b = abs($1 - preferred.y)
                    return a == b ? $0 < $1 : a < b
                }.prefix(12)
                centers += xs.flatMap { x in ys.map { CGPoint(x: x, y: $0) } }
                for y in 0...12 {
                    for x in 0...10 {
                        centers.append(CGPoint(x: area.minX + area.width * CGFloat(x) / 10,
                                               y: area.minY + area.height * CGFloat(y) / 12))
                    }
                }
                centers.sort {
                    let a = hypot($0.x - preferred.x, $0.y - preferred.y)
                    let b = hypot($1.x - preferred.x, $1.y - preferred.y)
                    return a == b ? ($0.y == $1.y ? $0.x < $1.x : $0.y < $1.y) : a < b
                }
                for center in centers {
                    let bounds = CGRect(x: center.x - halfW, y: center.y - halfH, width: local.width, height: local.height)
                    guard area.contains(bounds), allowsForeground(bounds, foreground: foreground), !occupied.contains(where: {
                        $0.insetBy(dx: -gap, dy: -gap).intersects(bounds)
                    }) else { continue }
                    transform.position = CGPoint(x: center.x - local.midX, y: center.y - local.midY)
                    result[index] = Placement(transform: transform, bounds: bounds)
                    occupied.append(bounds)
                    break
                }
                if result[index] == nil { break }
            }
            if result.count == inputs.count { return inputs.indices.compactMap { result[$0] } }
        }
        return nil
    }

    /// Foreground labels/accents may touch a photo's edge, never cover its central content.
    static func allowsForeground(_ photo: CGRect, foreground: [CGRect]) -> Bool {
        var area: CGFloat = 0
        for overlay in foreground {
            let overlap = photo.intersection(overlay)
            if overlap.isNull || overlap.isEmpty { continue }
            let edgeBand = photo.insetBy(dx: photo.width * 0.14, dy: photo.height * 0.14)
            guard !overlap.intersects(edgeBand) else { return false }
            area += overlap.width * overlap.height
        }
        return area <= photo.width * photo.height * 0.12
    }

    /// Equal PHOTO widths, actual frame-edge gaps, and one translation for the entire stack.
    private static func compactStack(_ inputs: [Input], area: CGRect, canvas: CGRect, gap: CGFloat,
                                     obstacles: [CGRect], foreground: [CGRect]) -> [Placement]? {
        for factor in [CGFloat(1), 0.95, 0.90, 0.85, 0.80, 0.75, 0.70, 0.65, 0.60] {
            for stagger in [true, false] {
                var locals: [(DiaryTransform, CGRect)] = []
                for (index, input) in inputs.enumerated() {
                    let transform = DiaryTransform(position: .zero,
                        pivot: CGPoint(x: input.photoSize.width / 2, y: input.photoSize.height / 2),
                        scale: canvas.width * 0.75 / input.photoSize.width,
                        rotationDegrees: stagger && inputs.count > 1 ? (index == 0 ? -0.8 : 0.8) : 0,
                        flippedHorizontally: input.flippedHorizontally, flippedVertically: input.flippedVertically)
                    locals.append((transform, input.bounds.applying(transform.matrix)))
                }
                let totalHeight = locals.reduce(CGFloat.zero) { $0 + $1.1.height }
                let fit = min(1, area.width / (locals.map { $0.1.width }.max() ?? 1),
                              (area.height - gap * CGFloat(inputs.count - 1)) / totalHeight) * factor * 0.995
                guard fit > 0 else { continue }
                var stack: [Placement] = []
                var y: CGFloat = 0
                for (index, input) in inputs.enumerated() {
                    var transform = locals[index].0
                    transform.scale *= fit
                    guard transform.scale >= 0.05, transform.scale <= 20,
                          min(input.photoSize.width, input.photoSize.height) * transform.scale >= min(canvas.width, canvas.height) * 0.12 else { break }
                    let local = input.bounds.applying(transform.matrix)
                    transform.position = CGPoint(x: -local.midX, y: y - local.minY)
                    let bounds = input.bounds.applying(transform.matrix)
                    stack.append(Placement(transform: transform, bounds: bounds))
                    y = bounds.maxY + gap
                }
                guard stack.count == inputs.count else { continue }
                let union = stack.reduce(CGRect.null) { $0.union($1.bounds) }
                var offsets = [CGPoint(x: area.midX, y: area.midY - union.height / 2)]
                let xs = [area.midX, area.minX + union.width / 2, area.maxX - union.width / 2]
                    + obstacles.flatMap { [$0.minX - gap - union.width / 2, $0.maxX + gap + union.width / 2] }
                let ys = [area.midY - union.height / 2, area.minY, area.maxY - union.height]
                    + (obstacles + foreground).flatMap { [$0.minY - gap - union.height, $0.maxY + gap] }
                offsets += xs.flatMap { x in ys.map { CGPoint(x: x, y: $0) } }
                offsets.sort { hypot($0.x - area.midX, $0.y + union.height / 2 - area.midY) < hypot($1.x - area.midX, $1.y + union.height / 2 - area.midY) }
                for offset in offsets {
                    let result = stack.map { placement -> Placement in
                        var transform = placement.transform
                        transform.position.x += offset.x; transform.position.y += offset.y
                        return Placement(transform: transform, bounds: placement.bounds.offsetBy(dx: offset.x, dy: offset.y))
                    }
                    if result.allSatisfy({ placement in
                        area.contains(placement.bounds) && allowsForeground(placement.bounds, foreground: foreground)
                            && !obstacles.contains { $0.insetBy(dx: -gap, dy: -gap).intersects(placement.bounds) }
                    }) { return result }
                }
            }
        }
        return nil
    }

    static func slots(inputs: [Input], area: CGRect, gap: CGFloat, minimum: CGFloat) -> [CGRect] {
        let count = inputs.count
        func grid(columns: Int) -> [CGRect] {
            let rows = (count + columns - 1) / columns
            let w = (area.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
            let h = (area.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
            return inputs.indices.map { i in
                let row = i / columns, rowCount = min(columns, count - row * columns)
                let rowWidth = CGFloat(rowCount) * w + CGFloat(rowCount - 1) * gap
                return CGRect(x: area.midX - rowWidth / 2 + CGFloat(i % columns) * (w + gap),
                              y: area.minY + CGFloat(row) * (h + gap), width: w, height: h)
            }
        }
        if count == 1 { return [area] }
        if count == 2 {
            if inputs.allSatisfy({ $0.photoSize.width < $0.photoSize.height }) { return grid(columns: 2) }
            if inputs.allSatisfy({ $0.photoSize.width >= $0.photoSize.height }) { return grid(columns: 1) }
        }
        if count == 3 {
            let portraits = inputs.indices.filter { inputs[$0].photoSize.width < inputs[$0].photoSize.height }
            let landscapes = inputs.indices.filter { inputs[$0].photoSize.width >= inputs[$0].photoSize.height }
            if portraits.count == 2, let wide = landscapes.first {
                let upperH = (area.height - gap) * 0.59
                var output = [CGRect](repeating: .zero, count: 3)
                for (column, index) in portraits.enumerated() {
                    output[index] = CGRect(x: area.minX + CGFloat(column) * (area.width + gap) / 2,
                        y: area.minY, width: (area.width - gap) / 2, height: upperH)
                }
                output[wide] = CGRect(x: area.minX, y: area.minY + upperH + gap,
                    width: area.width, height: area.height - upperH - gap)
                return output
            }
        }
        if count == 4 { return grid(columns: 2) }
        // For mixed ratios and dense batches, pick the grid with the largest readable photo area.
        func score(_ slots: [CGRect]) -> CGFloat {
            zip(inputs, slots).reduce(0) { total, pair in
                let scale = min(pair.1.width / pair.0.bounds.width, pair.1.height / pair.0.bounds.height)
                return total + pair.0.photoSize.width * pair.0.photoSize.height * scale * scale
            }
        }
        let columns = count >= 5 ? (count <= 6 ? 2...3 : 2...6) : 1...3
        let candidates = columns.map { grid(columns: min(count, $0)) }
        let readable = candidates.filter { slots in
            zip(inputs, slots).allSatisfy { input, slot in
                let scale = min(slot.width / input.bounds.width, slot.height / input.bounds.height) * 0.92
                return min(input.photoSize.width, input.photoSize.height) * scale >= minimum
            }
        }
        return (readable.isEmpty ? candidates : readable).max { score($0) < score($1) } ?? []
    }
}
