import SwiftUI
import MetalKit

public struct MetalViewRepresentable: UIViewRepresentable {
    
    public init() {}
    
    public func makeCoordinator() -> RendererCoordinator {
        RendererCoordinator()
    }
    
    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported")
        }
        
        mtkView.device = defaultDevice
        mtkView.framebufferOnly = false
        mtkView.colorPixelFormat = .bgra8Unorm
        
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true
        
        let renderer = MetalGyroRenderer(device: defaultDevice)
        renderer.view = mtkView
        
        context.coordinator.renderer = renderer
        mtkView.delegate = renderer
        
        return mtkView
    }
    
    public func updateUIView(_ uiView: MTKView, context: Context) {}
    
    public class RendererCoordinator {
        var renderer: MetalGyroRenderer?
    }
}


