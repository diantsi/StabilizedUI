import CoreMotion
import MetalKit
import QuartzCore

class MetalGyroRenderer: NSObject, MTKViewDelegate {

    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState!
    var vertexBuffer: MTLBuffer!
    var texture: MTLTexture?
    weak var view: MTKView?
    private let motionManager = CMMotionManager()
    var displayLink: CADisplayLink?

    var currentOffset: SIMD2<Float> = .zero

        //for picture of persyk
        let scaleX: Float = 0.7
        let scaleY: Float = 0.32
    
        lazy var vertexData: [Float] = [
            -scaleX,  scaleY, 0.0, 1.0,   0.0, 0.0,
            -scaleX, -scaleY, 0.0, 1.0,   0.0, 1.0,
             scaleX,  scaleY, 0.0, 1.0,   1.0, 0.0,
             scaleX, -scaleY, 0.0, 1.0,   1.0, 1.0
        ]

//    //poem picture
//    let scaleX: Float = 1.5
//    let scaleY: Float = 1.25
//    //        let scaleX: Float = 0.7
//    //        let scaleY: Float = 0.58
//
//
//    lazy var vertexData: [Float] = [
//        -scaleX, scaleY, 0.0, 1.0, 0.0, 0.0,
//        -scaleX, -scaleY, 0.0, 1.0, 0.0, 1.0,
//        scaleX, scaleY, 0.0, 1.0, 1.0, 0.0,
//        scaleX, -scaleY, 0.0, 1.0, 1.0, 1.0,
//    ]

    
    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        super.init()
        setupPipeline()
        setupVertexBuffers()
        loadTexture(imageName: "persyk")
        startMotionTracking()
        setupDisplayLink()
    }

    func setupPipeline() {
        guard let library = device.makeDefaultLibrary() else { return }
        let vertexFunction = library.makeFunction(name: "vertex_main")
        let fragmentFunction = library.makeFunction(name: "fragment_main")
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = 16
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = 24
        descriptor.vertexDescriptor = vertexDescriptor
        pipelineState = try? device.makeRenderPipelineState(
            descriptor: descriptor
        )
    }

    func setupVertexBuffers() {
        vertexBuffer = device.makeBuffer(
            bytes: vertexData,
            length: vertexData.count * MemoryLayout<Float>.size,
            options: []
        )
    }

    func loadTexture(imageName: String) {
        let loader = MTKTextureLoader(device: device)
        texture = try? loader.newTexture(
            name: imageName,
            scaleFactor: 1.0,
            bundle: nil,
            options: [.SRGB: false]
        )
    }

    func setupDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(gameLoop))
        displayLink?.add(to: .current, forMode: .common)
    }

    private var baselineRoll: Double?
    private var baselinePitch: Double?

    @objc func gameLoop() {
        updateMotion()
        view?.draw()
    }

    func startMotionTracking() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates()
    }

    
    
    let smooth: Float = 0.15
    let sensitivity: Float = 0.4

    private var targetOffset: SIMD2<Float> = .zero
    let maxOffset: Float = 0.15


    func updateMotion() {
        guard let data = motionManager.deviceMotion else { return }

        let currentRoll = data.attitude.roll
        let currentPitch = data.attitude.pitch


//        print("currentRoll " + "\(currentRoll)\n" + "currentPitch " + "\(currentPitch)\n\n")

        if baselineRoll == nil || baselinePitch == nil {
            baselineRoll = currentRoll
            baselinePitch = currentPitch
            return
        }

        guard let baseRoll = baselineRoll, let basePitch = baselinePitch else {
            return
        }

        let deltaRoll = Float(baseRoll - currentRoll)
        let deltaPitch = Float(currentPitch - basePitch)
        
        
        let targetX = deltaRoll * sensitivity
        let targetY = deltaPitch * sensitivity

        let newX = max(-maxOffset, min(maxOffset, targetX))
        let newY = max(-maxOffset, min(maxOffset, targetY))
        
        targetOffset = SIMD2<Float>(newX, newY)
        
        currentOffset.x += (targetOffset.x - currentOffset.x) * smooth
        currentOffset.y += (targetOffset.y - currentOffset.y) * smooth
        
        
        
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let pipelineState = pipelineState, let texture = texture
        else { return }

        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 1
        )

        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: descriptor
        )!
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(
            &currentOffset,
            length: MemoryLayout<SIMD2<Float>>.stride,
            index: 1
        )
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4
        )
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
