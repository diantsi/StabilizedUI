import CoreMotion
import MetalKit
import QuartzCore
import SwiftUI
import simd


public struct MetalGyroView<Content: View>: UIViewRepresentable {

    public var maxOffset: Float
    public var smoothing: Float
    public var motionRate: Double
    public var scale: SIMD2<Float>

    private let content: () -> Content

    public init(
        maxOffset: Float = 0.04,
        smoothing: Float = 0.4,
        motionRate: Double = 200,
        scale: SIMD2<Float> = .one,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.maxOffset  = maxOffset
        self.smoothing  = smoothing
        self.motionRate = motionRate
        self.scale      = scale
        self.content    = content
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIView(context: Context) -> GyroHostView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device.")
        }
        let host = GyroHostView(
            device: device,
            maxOffset: maxOffset,
            smoothing: smoothing,
            motionRate: motionRate,
            scale: scale
        )
        context.coordinator.host = host
        host.contentProvider = { [content] size in
            AnyView(content().frame(width: size.width, height: size.height))
        }
        return host
    }

    public func updateUIView(_ uiView: GyroHostView, context: Context) {
        uiView.scale = scale
        uiView.contentProvider = { [content] size in
            AnyView(content().frame(width: size.width, height: size.height))
        }
        if uiView.bounds.size != .zero {
            uiView.rasterizeContent()
        }
    }

    public final class Coordinator {
        var host: GyroHostView?
        deinit { host?.tearDown() }
    }
}
