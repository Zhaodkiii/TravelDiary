import SwiftUI
import MetalKit

/// GPU analytic trajectories keep the animation deterministic across frame rates and pauses.
struct DiaryCosmicSurface: UIViewRepresentable {
    let photos: [UIImage]
    let stickers: [UIImage]
    let result: UIImage?
    let time: Double
    let ending: Double
    var canvasFrame = CGRect.zero
    let active: Bool
    let onFailure: () -> Void

    func makeCoordinator() -> DiaryCosmicRenderer { DiaryCosmicRenderer() }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.isOpaque = true
        view.isUserInteractionEnabled = false
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.framebufferOnly = true
        view.clearColor = MTLClearColorMake(0.008, 0.012, 0.035, 1)
        do { try context.coordinator.prepare(view) }
        catch { NSLog("Diary cosmic renderer: %@", String(describing: error)); DispatchQueue.main.async { onFailure() } }
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(photos: photos, stickers: stickers, result: result, time: time, ending: ending)
        context.coordinator.canvasFrame = canvasFrame
        if active { view.setNeedsDisplay() }
    }
}

@MainActor final class DiaryCosmicRenderer: NSObject, MTKViewDelegate {
    var canvasFrame = CGRect.zero
    private var device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var background: MTLRenderPipelineState?
    private var cards: MTLRenderPipelineState?
    private var stars: MTLRenderPipelineState?
    private var artwork: MTLRenderPipelineState?
    private var atlas: MTLTexture?
    private var resultTexture: MTLTexture?
    private var sourceIDs: [ObjectIdentifier] = []
    private var resultID: ObjectIdentifier?
    private var time: Float = 0
    private var ending: Float = -1
    private var cardCount: Float = 0
    private var photoCount: Float = 0
    private var resultAspect: Float = 1.5

    func prepare(_ view: MTKView) throws {
        guard let device = view.device, let queue = device.makeCommandQueue() else { throw CocoaError(.featureUnsupported) }
        self.device = device; self.queue = queue
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        func pipeline(_ vertex: String, _ fragment: String, additive: Bool = false) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = view.colorPixelFormat
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        background = try pipeline("cosmicQuad", "cosmicSpace")
        artwork = try pipeline("cosmicQuad", "cosmicArtwork")
        cards = try pipeline("cosmicCard", "cosmicCardColor")
        stars = try pipeline("cosmicStar", "cosmicStarColor", additive: true)
        atlas = try texture(Self.emptyAtlas())
        resultTexture = atlas
    }

    func update(photos: [UIImage], stickers: [UIImage], result: UIImage?, time: Double, ending: Double) {
        self.time = Float(max(0, time)); self.ending = Float(ending)
        let images = Array(photos.prefix(8)) + Array(stickers.prefix(8))
        let ids = images.map(ObjectIdentifier.init)
        if sourceIDs != ids {
            sourceIDs = ids
            cardCount = Float(images.count); photoCount = Float(min(photos.count, 8))
            if let image = Self.makeAtlas(images, photoCount: Int(photoCount)), let loaded = try? texture(image) { atlas = loaded }
        }
        if resultID != result.map(ObjectIdentifier.init) {
            resultID = result.map(ObjectIdentifier.init)
            if let result, let loaded = try? texture(result) {
                resultTexture = loaded
                resultAspect = Float(result.size.width / max(1, result.size.height))
            }
        }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let background, let artwork, let cards, let stars, let atlas, let resultTexture,
              let descriptor = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue?.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        let frame = view.convert(canvasFrame, from: nil)
        let width = max(1, view.bounds.width), height = max(1, view.bounds.height)
        let centerX = frame.isEmpty ? 0 : Float(frame.midX / width * 2 - 1)
        let centerY = frame.isEmpty ? 0 : Float(1 - frame.midY / height * 2)
        let fitWidth = min(frame.width, frame.height * CGFloat(resultAspect))
        let fitHeight = fitWidth / CGFloat(resultAspect)
        // Twelve floats, matching the Metal uniform layout exactly.
        // Freeze the source constellation at completion; the finale owns its motion.
        let sourceTime = ending >= 0 ? max(0, time - ending) : time
        // Stretch only contraction to 1.5 seconds; preserve the subsequent reveal rhythm.
        let finaleTime: Float = ending < 0 ? -1 : ending <= 1.5 ? ending * (0.48 / 1.5) : ending - 1.02
        var uniforms: [Float] = [sourceTime, finaleTime, Float(view.drawableSize.width / max(1, view.drawableSize.height)),
                                 cardCount, photoCount, resultAspect, Float(view.drawableSize.width), 0, centerX, centerY, Float(fitWidth / width), Float(fitHeight / height)]
        encoder.setVertexBytes(&uniforms, length: 48, index: 0)
        encoder.setFragmentBytes(&uniforms, length: 48, index: 0)
        encoder.setFragmentTexture(atlas, index: 0)
        encoder.setVertexTexture(atlas, index: 0)
        encoder.setFragmentTexture(resultTexture, index: 1)
        encoder.setRenderPipelineState(background)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        if ending >= 0 {
            encoder.setRenderPipelineState(artwork)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
        if (ending < 0 || ending < 1.5) && cardCount > 0 {
            encoder.setRenderPipelineState(cards)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: Int(cardCount))
        }
        encoder.setRenderPipelineState(stars)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: 12288)
        encoder.endEncoding()
        command.present(drawable); command.commit()
    }

    private func texture(_ image: UIImage) throws -> MTLTexture {
        guard let device else { throw CocoaError(.featureUnsupported) }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let ratio = min(1, 1800 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * ratio), height: max(1, image.size.height * ratio))
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let cgImage = normalized.cgImage else { throw CocoaError(.fileReadCorruptFile) }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw CocoaError(.featureUnsupported) }
        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileReadCorruptFile) }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: width * 4)
        }
        return texture
    }
    private static func emptyAtlas() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { output in
            UIColor.white.setFill(); output.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
    private static func makeAtlas(_ images: [UIImage], photoCount: Int) -> UIImage? {
        guard !images.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: format).image { output in
            for (index, image) in images.enumerated() {
                let cell = CGRect(x: (index % 4) * 256, y: (index / 4) * 256, width: 256, height: 256)
                let scale = min(232 / image.size.width, 232 / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let rect = CGRect(x: cell.midX - size.width / 2, y: cell.midY - size.height / 2, width: size.width, height: size.height)
                if index < photoCount {
                    UIColor(white: 0.96, alpha: 1).setFill()
                    output.fill(rect.insetBy(dx: -5, dy: -5))
                }
                image.draw(in: rect)
            }
        }
    }

    private static let shader = #"""
#include <metal_stdlib>
using namespace metal;
struct Uniforms { float time, ending, aspect, count, photos, resultAspect, width, padding, centerX, centerY, extentX, extentY; };
struct Quad { float4 position [[position]]; float2 uv; float alpha; float index; };
struct Star { float4 position [[position]]; float size [[point_size]]; float4 color; };
constant float2 corners[6] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(-1,1),float2(1,-1),float2(1,1)};
float hash(float n) { return fract(sin(n*127.1+311.7)*43758.5453); }
float deposit(float2 uv) {
    float2 grid=uv*float2(10,8);
    float2 cell=floor(grid), f=fract(grid); f=f*f*(3.-2.*f);
    float n=cell.x+cell.y*17.;
    return 1.5+1.2*mix(mix(hash(n),hash(n+1),f.x),mix(hash(n+17),hash(n+18),f.x),f.y);
}
float ease(float a, float b, float t) { return smoothstep(a,b,t); }
// Replenish photo-to-star streams while production is running, with no timed finish.
// Each material has its own phase so the scene never resets as a whole.
float materialTime(float index, float time) { return fmod(max(0.,time)+index*.85,14.); }
float2 resultSize(constant Uniforms &u) { if(u.extentX>0 && u.extentY>0) return float2(u.extentX,u.extentY); return float2(min(.88,.56*u.resultAspect/u.aspect),min(.56,.88*u.aspect/u.resultAspect)); }
float2 atlasUV(float index,float2 uv) { return (float2(fmod(index,4.0),floor(index/4.0))+uv)/4.; }
float3 project(float3 p,constant Uniforms &u) { float depth=max(.7,3.2-p.z); return float3(p.x/depth/u.aspect,p.y/depth,p.z); }
float3 orbit(float i,constant Uniforms &u) {
    float a=i*2.39996+u.time*(.42+.07*sin(i));
    return float3(cos(a)*.95,sin(a)*.90,sin(a*.7+i)*.65);
}
vertex Quad cosmicQuad(uint id [[vertex_id]]) {
    Quad out; out.position=float4(corners[id],0,1); out.uv=corners[id]*float2(.5,-.5)+.5; out.alpha=1; out.index=0; return out;
}
fragment float4 cosmicSpace(Quad in [[stage_in]],constant Uniforms &u [[buffer(0)]]) {
    float2 p=(in.uv-.5)*float2(u.aspect,1);
    float r=length(p);
    float cloud=sin(p.x*9+u.time*.03)*sin(p.y*7-p.x*4)+sin(p.x*21+p.y*11)*.2;
    float3 color=float3(.005,.009,.025)+float3(.028,.016,.068)*exp(-r*3)*(cloud*.3+.6);
    float core=exp(-r*r/.004);
    color+=float3(.22,.32,.6)*core*.22;
    if(u.ending>=0) {
        float e=u.ending;
        float flash=exp(-pow((e-.65)*8,2));
        float ring=exp(-pow((r-(e-.5)*.95)*65,2))*(1-ease(.7,1.5,e))*step(.5,e);
        color+=float3(.45,.57,.8)*flash+float3(.18,.42,.7)*ring;
        color*=1-ease(3.8,5.5,e)*.6;
    }
    return float4(color,1);
}
vertex Quad cosmicCard(uint id [[vertex_id]],uint instance [[instance_id]],constant Uniforms &u [[buffer(0)]]) {
    Quad out; float3 center=orbit(float(instance),u); float a=sin(u.time*.4+instance)*.18;
    float2 q=corners[id]*.34;
    q=float2(q.x*cos(a)-q.y*sin(a),q.x*sin(a)+q.y*cos(a));
    float3 p=center+float3(q,0);
    float contraction=u.ending<0 ? 0 : ease(0,.48,u.ending);
    float turn=contraction*1.3;
    p.xy=float2(p.x*cos(turn)-p.y*sin(turn),p.x*sin(turn)+p.y*cos(turn));
    float3 position=project(p*(1-contraction),u);
    out.position=float4(position.xy,0,1); out.uv=corners[id]*float2(.5,-.5)+.5;
    out.alpha=ease(0,.8,u.time)*(1-(u.ending<0 ? 0 : ease(0,.35,u.ending))); out.index=float(instance); return out;
}
fragment float4 cosmicCardColor(Quad in [[stage_in]],texture2d<float> atlas [[texture(0)]],constant Uniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear,address::clamp_to_edge);
    float4 c=atlas.sample(s,atlasUV(in.index,in.uv));
    // Peel each photo into particles from one edge, rather than fading the whole card.
    float release=3.+in.uv.x*2.;
    float phase=materialTime(in.index,u.time);
    c.a*=in.alpha*ease(0,1.,phase)*(1-ease(release,release+1.2,phase)); return c;
}
vertex Star cosmicStar(uint id [[vertex_id]],constant Uniforms &u [[buffer(0)]],texture2d<float> atlas [[texture(0)]]) {
    constexpr sampler s(filter::linear,address::clamp_to_edge);
    Star out; float n=float(id); float h=hash(n); float h2=hash(n+71);
    float2 cell=float2(id%128,id/128);
    float2 targetUV=(cell+.1+.8*float2(hash(n+5),hash(n+13)))/float2(128,96);
    float index=fmod(n,max(1.,u.count));
    float2 sourceUV=float2(hash(n+17),hash(n+35));
    float4 source=atlas.sample(s,atlasUV(index,sourceUV));
    float radius=.13+pow(h,.65)*2.7;
    float angle=h*13+fmod(n,4.)*1.5708+u.time*(.2+.16/(radius+.3))+(hash(n+21)-.5)*.22;
    float3 galaxy=float3(cos(angle)*radius,sin(angle)*radius*.47,(h2-.5)*.65+sin(angle)*radius*.22);
    // Keep the galaxy open for the entire real production wait.
    float2 local=(sourceUV-float2(.5))*float2(.68,-.68);
    float tilt=sin(u.time*.4+index)*.18;
    local=float2(local.x*cos(tilt)-local.y*sin(tilt),local.x*sin(tilt)+local.y*cos(tilt));
    float3 original=orbit(index,u)+float3(local,0);
    float phase=materialTime(index,u.time);
    float release=3.+sourceUV.x*2.;
    float departure=ease(release,release+3.,phase);
    float3 p=mix(original,galaxy,departure);
    float alpha=mix(source.a,1.,departure)*ease(release-.3,release+.8,phase)*(1-ease(12.,14.,phase));
    float3 color=mix(max(source.rgb,float3(.08)),mix(float3(.25,.50,1),float3(1,.64,.29),h2),.55*ease(4,9,u.time));
    float size=1.2+pow(h2,12.)*4.;
    float3 projected=project(p,u);
    if(u.ending>=0) {
        float e=u.ending;
        float contraction=ease(0,.48,e);
        float turn=contraction*1.3;
        float3 initial=p;
        initial.xy=float2(initial.x*cos(turn)-initial.y*sin(turn),initial.x*sin(turn)+initial.y*cos(turn));
        float3 compressed=initial*(1-contraction);
        float a=h*6.283185;
        float speed=.4+hash(n+9)*1.4;
        float3 blast=float3(cos(a)*speed,sin(a)*speed,(h2-.5)*2.)*(1-exp(-max(0.,e-.5)*4.));
        float3 moving=mix(compressed,blast,ease(.48,.65,e));
        float2 screen=project(moving,u).xy;
        float arrival=deposit(targetUV);
        float settle=ease(1.15,arrival+.8,e);
        float2 target=(targetUV*float2(2,-2)+float2(-1,1))*resultSize(u)+float2(u.centerX,u.centerY);
        screen=mix(screen,target,settle);
        screen.y+=sin(settle*3.14159)*.18;
        projected.xy=screen;
        color=mix(color,float3(1.,.86,.6),ease(1.,3.,e));
        alpha=mix(alpha,.5+.5*h2,ease(.35,.65,e))*(1-ease(arrival+.8,arrival+1.7,e));
        // Reduce additive overlap during collapse so the core does not become a white oval.
        float density=mix(1.,.035,contraction)*(1-ease(.48,.52,e));
        alpha*=mix(density,1.,ease(.52,.65,e));
        size=mix(size*(1-.65*contraction),1.5+pow(h2,8.)*7.,ease(.52,.65,e))*(1-ease(3.8,5.2,e));
    }
    out.position=float4(projected.xy,0,1);
    out.size=clamp(size*u.width/390.,1.,32.);
    out.color=float4(color,alpha*.7);
    return out;
}
fragment float4 cosmicStarColor(Star in [[stage_in]],float2 point [[point_coord]]) {
    float r=length(point-.5)*2;
    float glow=exp(-r*r*5.)*(1-smoothstep(.7,1.,r));
    return float4(in.color.rgb,in.color.a*glow);
}
fragment float4 cosmicArtwork(Quad in [[stage_in]],constant Uniforms &u [[buffer(0)]],texture2d<float> result [[texture(1)]]) {
    constexpr sampler s(filter::linear,address::clamp_to_edge);
    float2 extent=resultSize(u);
    float2 uv=(in.uv-(.5+float2(u.centerX,-u.centerY)*.5))/extent+.5;
    if(any(uv<0)||any(uv>1)) return float4(0);
    float arrival=deposit(uv);
    float visibility=ease(arrival+.55,arrival+1.25,u.ending);
    // Overlapping soft deposits spread across the paper, then resolve to the untouched image.
    visibility=mix(visibility,1.,ease(3.4,4.7,u.ending));
    float4 color=result.sample(s,uv);
    color.rgb+=float3(.13,.09,.025)*visibility*(1-visibility);
    color.a*=visibility;
    return color;
}
"""#
}
