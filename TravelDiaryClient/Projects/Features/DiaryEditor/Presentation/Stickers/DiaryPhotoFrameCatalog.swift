import UIKit

/// Parameters are encoded in the catalog identifier; generated pixels travel with saved documents.
enum DiaryPhotoFrameCatalog {
    struct Item: Identifiable {
        let id: String
        let title: String
        let opening: CGRect
        var image: UIImage? { DiaryPhotoFrameCatalog.render(self) }
    }
    static let names = ["手撕纸", "简洁纸边", "拍立得"]
    static func generated(style: Int = 0, roughness: Double = 0.4, width: Double = 0.06,
                          shade: Double = 0.2, color: Int = 0, seed: Int = 1, ratio: Double = 1.333) -> Item {
        let w = 1000.0, h = w / max(0.2, ratio), b = min(w, h) * width
        let bottom = style == 2 ? b * 3 : b
        let margin = 40.0
        let opening = CGRect(x: (b + margin)/(w + 2*b + 2*margin), y: (b + margin)/(h+b+bottom+2*margin),
                             width: w/(w+2*b+2*margin), height: h/(h+b+bottom+2*margin))
        return Item(id: "generated|\(style)|\(roughness)|\(width)|\(shade)|\(color)|\(seed)|\(ratio)", title: names[style], opening: opening)
    }
    static var items: [Item] { (0..<3).map { generated(style: $0) } }
    static var defaultFrame: Item { generated() }
    static func render(_ item: Item) -> UIImage? {
        let p = item.id.split(separator: "|").map(String.init)
        guard p.count == 8, let style = Int(p[1]), let rough = Double(p[2]), let shade = Double(p[4]),
              let color = Int(p[5]), let seed = Int(p[6]) else { return nil }
        let opening = item.opening
        let size = CGSize(width: 1000/opening.width, height: (1000/(Double(p[7]) ?? 1.333))/opening.height)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let ctx = renderer.cgContext
            let paper = CGRect(origin: .zero, size: size).insetBy(dx: 40, dy: 40)
            let hole = CGRect(x: opening.minX*size.width, y: opening.minY*size.height,
                              width: opening.width*size.width, height: opening.height*size.height)
            let path = UIBezierPath()
            let corners = [CGPoint(x:paper.minX,y:paper.minY), CGPoint(x:paper.maxX,y:paper.minY),
                           CGPoint(x:paper.maxX,y:paper.maxY), CGPoint(x:paper.minX,y:paper.maxY)]
            for edge in 0..<4 {
                let a = corners[edge], b = corners[(edge+1)%4]
                let length = hypot(b.x-a.x,b.y-a.y)
                let count = max(2, Int(length/5))
                for i in 0..<count {
                    let t = CGFloat(i)/CGFloat(count)
                    let phase = Double(i) + Double(seed % 10000)*1.37 + Double(edge)*71
                    let noise = sin(phase*0.23)*0.55 + sin(phase*1.71)*0.3 + sin(phase*2.93)*0.15
                    let displacement = style == 0 ? CGFloat(noise*rough*14)*sin(.pi*t) : 0
                    let pt = CGPoint(x:a.x+(b.x-a.x)*t-(b.y-a.y)/length*displacement,
                                     y:a.y+(b.y-a.y)*t+(b.x-a.x)/length*displacement)
                    if edge == 0 && i == 0 { path.move(to:pt) } else { path.addLine(to:pt) }
                }
            }
            path.close()
            let colors: [UIColor] = [.init(white:0.97,alpha:1), .init(red:0.94,green:0.91,blue:0.84,alpha:1),
                                     .init(red:0.84,green:0.91,blue:0.96,alpha:1), .init(red:0.91,green:0.85,blue:0.87,alpha:1),
                                     .init(red:0.84,green:0.9,blue:0.83,alpha:1)]
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width:0,height:shade*10), blur: shade*24, color: UIColor.black.withAlphaComponent(shade*0.5).cgColor)
            colors[max(0,min(color,colors.count-1))].setFill(); path.fill()
            ctx.restoreGState()
            ctx.clear(hole)
        }
    }
}
