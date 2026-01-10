import CoreMotion
import MetalKit
import QuartzCore
import simd

class MetalGyroRenderer: NSObject, MTKViewDelegate {

    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState!
    var vertexBuffer: MTLBuffer!
    var texture: MTLTexture?
    weak var view: MTKView?
    private let motionManager = CMMotionManager()

    var currentOffset: SIMD2<Float> = .zero

    //for picture of persyk
    let scaleX: Float = 0.7
    let scaleY: Float = 0.32

    lazy var vertexData: [Float] = [
        -scaleX, scaleY, 0.0, 1.0, 0.0, 0.0,
        -scaleX, -scaleY, 0.0, 1.0, 0.0, 1.0,
        scaleX, scaleY, 0.0, 1.0, 1.0, 0.0,
        scaleX, -scaleY, 0.0, 1.0, 1.0, 1.0,
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

    private let maxOffset: Float = 0.12
    private let smoothing: Float = 0.5

    //    var offset: CGSize = .zero

    private var initialRoll: Float?
    private var initialPitch: Float?
    private var initialQuaternion: CMQuaternion?

    //    func startMotionTracking() {
    //                guard motionManager.isDeviceMotionAvailable else { return }
    //                motionManager.deviceMotionUpdateInterval = 1 / 200
    //
    //                motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
    //                    guard let self = self, let m = motion else { return }
    //
    //                    let currentQ = m.attitude.quaternion
    //
    //                    if self.initialQuaternion == nil {
    //                        self.initialQuaternion = currentQ
    //                    }
    //
    //                    guard let initialQ = self.initialQuaternion else { return }
    //
    //
    //                    let inversionQ = CMQuaternion(x: -initialQ.x, y: -initialQ.y, z: -initialQ.z, w: initialQ.w)
    //                    let targetG = multiplyQuaternions(currentQ, inversionQ)
    //
    //                    // 3. Компоненти x та y відносного кватерніона прямо пропорційні нахилу
    //                    // Множимо на 2.0, бо значення компонентів кватерніона зазвичай вдвічі менші за кути в радіанах
    //                    let targetX = -clamp(Float(targetG.y) * 2.0, -self.maxOffset, self.maxOffset)
    //                    let targetY = clamp(Float(targetG.x) * 2.0, -self.maxOffset, self.maxOffset)
    //
    //
    //                    let newX = currentOffset.x + (targetX - currentOffset.x) * self.smoothing
    //                    let newY = currentOffset.y + (targetY - currentOffset.y) * self.smoothing
    //
    //                    self.currentOffset = SIMD2<Float>(newX, newY)
    //                    self.view?.setNeedsDisplay()
    //                }
    //            }
    //
    //            private func multiplyQuaternions(_ q1: CMQuaternion, _ q2: CMQuaternion) -> CMQuaternion {
    //                return CMQuaternion(
    //                    x: q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y,
    //                    y: q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x,
    //                    z: q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w,
    //                    w: q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z
    //                )
    //            }
    //

    func startMotionTracking() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1 / 200

        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: .main
        ) {
            [weak self] motion, _ in
            guard let self, let m = motion else { return }

            let roll = Float(m.attitude.roll)
            let pitch = Float(m.attitude.pitch)

            if self.initialRoll == nil {
                self.initialRoll = roll
                self.initialPitch = pitch
            }

            let deltaX = roll - (self.initialRoll ?? 0.0)
            let deltaY = pitch - (self.initialPitch ?? 0.0)

            let targetX = -clamp(
                deltaX * 0.2,
                -self.maxOffset,
                self.maxOffset
            )
            let targetY = clamp(
                deltaY * 0.2,
                -self.maxOffset,
                self.maxOffset
            )

            let newX =
                currentOffset.x + (targetX - currentOffset.x) * self.smoothing
            let newY =
                currentOffset.y + (targetY - currentOffset.y) * self.smoothing

            currentOffset = SIMD2<Float>(newX, newY)

            self.view?.setNeedsDisplay()
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    private func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        min(max(v, lo), hi)
    }

    var lastTimestamp: TimeInterval = 0.0
    var velocity = SIMD2<Float>(0, 0)
    var position = SIMD2<Float>(0, 0)

    func updateMotion(data: CMDeviceMotion) {

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
