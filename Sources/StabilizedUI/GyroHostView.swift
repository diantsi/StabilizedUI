//
//  GyroHostView.swift
//  StabilizedUI
//
//  Created by Діана Цісарук on 05.03.2026.
//
import CoreMotion
import MetalKit
import QuartzCore
import SwiftUI
import simd

public final class GyroHostView: UIView {

    var contentProvider: ((CGSize) -> AnyView)?
    var scale: SIMD2<Float> = .one {
        didSet { renderer.quadScale = scale }
    }

    private let mtkView: MTKView
    private let renderer: MetalGyroRenderer
    private var lastRasterizedSize: CGSize = .zero

    init(
        device: MTLDevice,
        maxOffset: Float,
        smoothing: Float,
        motionRate: Double,
        scale: SIMD2<Float>
    ) {
        self.scale = scale

        let mtk = MTKView(frame: .zero, device: device)
        mtk.colorPixelFormat      = .bgra8Unorm
        mtk.framebufferOnly       = true
        mtk.clearColor            = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtk.isPaused              = true
        mtk.enableSetNeedsDisplay = false
        mtk.autoresizingMask      = [.flexibleWidth, .flexibleHeight]
        self.mtkView = mtk

        self.renderer = MetalGyroRenderer(
            device: device,
            mtkView: mtk,
            maxOffset: maxOffset,
            smoothing: smoothing,
            motionRate: motionRate
        )
        renderer.quadScale = scale
        mtk.delegate = renderer

        super.init(frame: .zero)
        addSubview(mtk)
        renderer.startDisplayLink()
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func layoutSubviews() {
        super.layoutSubviews()
        mtkView.frame = bounds
        let size = bounds.size
        guard size != .zero, size != lastRasterizedSize else { return }
        lastRasterizedSize = size
        rasterizeContent()
    }

    func rasterizeContent() {
        let size = bounds.size
        guard size != .zero, let provider = contentProvider else {
            print("[MetalGyroView] skip: size=\(bounds.size) provider=\(contentProvider == nil ? "nil" : "ok")")
            return
        }

        let ir = ImageRenderer(content: provider(size))
        ir.proposedSize = .init(size)
        ir.scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 3

        guard let cgImage = ir.cgImage else {
            print("[MetalGyroView] cgImage nil — size:\(size) scale:\(ir.scale)")
            return
        }
        print("[MetalGyroView] cgImage ok: \(cgImage.width)x\(cgImage.height)")
        let r = renderer
        DispatchQueue.global(qos: .userInitiated).async {
            r.uploadTexture(cgImage: cgImage)
        }
    }

    func tearDown() { renderer.tearDown() }
}






