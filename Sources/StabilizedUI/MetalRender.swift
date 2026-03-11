import CoreMotion
import MetalKit
import os
import QuartzCore
import simd


final class MetalGyroRenderer: NSObject, MTKViewDelegate {


    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let quadBuffer: MTLBuffer


    private static let maxFramesInFlight = 3
    private let uniformBuffers: [MTLBuffer]
    private let frameSemaphore = DispatchSemaphore(value: maxFramesInFlight)
    private var currentBufferIndex = 0


    private var texture: MTLTexture?
    private let textureLock = NSLock()


    private let motionManager = CMMotionManager()
    private let maxOffset: Float
    private let smoothing: Float
    private let motionRate: Double

    private var _targetOffset:  SIMD3<Float> = SIMD3(0, 0, 1)
    private var currentOffset:  SIMD3<Float> = SIMD3(0, 0, 1)

    private var referenceQuaternion: CMQuaternion?

    private var lpX: Float = 0
    private var lpY: Float = 0

    private var offsetLock = os_unfair_lock()

    private var hasNewMotionData = false

    private var targetOffset: SIMD3<Float> {
        get {
            os_unfair_lock_lock(&offsetLock)
            defer { os_unfair_lock_unlock(&offsetLock) }
            return _targetOffset
        }
        set {
            os_unfair_lock_lock(&offsetLock)
            _targetOffset = newValue
            os_unfair_lock_unlock(&offsetLock)
        }
    }


    private var displayLink: CADisplayLink?
    private weak var mtkView: MTKView?

    var quadScale: SIMD2<Float> = .one


    init(
        device: MTLDevice,
        mtkView: MTKView,
        maxOffset: Float,
        smoothing: Float,
        motionRate: Double
    ) {
        self.device       = device
        self.mtkView      = mtkView
        self.maxOffset    = maxOffset
        self.smoothing    = smoothing
        self.motionRate   = motionRate
        self.commandQueue = device.makeCommandQueue()!

        let library: MTLLibrary
        if let lib = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            library = lib
        } else if let lib = device.makeDefaultLibrary() {
            library = lib
        } else {
            fatalError("[MetalGyroRenderer] Cannot find Metal library. Переконайтесь що Shaders.metal є в target/package.")
        }

        let pd = MTLRenderPipelineDescriptor()
        pd.label            = "MetalGyro"
        pd.vertexFunction   = library.makeFunction(name: "vertex_main")
        pd.fragmentFunction = library.makeFunction(name: "fragment_main")
        pd.colorAttachments[0].pixelFormat = .bgra8Unorm

        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float4; vd.attributes[0].offset = 0;  vd.attributes[0].bufferIndex = 0
        vd.attributes[1].format = .float2; vd.attributes[1].offset = 16; vd.attributes[1].bufferIndex = 0
        vd.layouts[0].stride = 24
        pd.vertexDescriptor  = vd

        self.pipelineState = try! device.makeRenderPipelineState(descriptor: pd)

        let quad: [Float] = [
            -1,  1, 0, 1,  0, 0,
            -1, -1, 0, 1,  0, 1,
             1,  1, 0, 1,  1, 0,
             1, -1, 0, 1,  1, 1,
        ]
        self.quadBuffer = device.makeBuffer(
            bytes: quad,
            length: quad.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )!

        self.uniformBuffers = (0..<MetalGyroRenderer.maxFramesInFlight).map { i in
            let b = device.makeBuffer(
                length: MemoryLayout<SIMD4<Float>>.stride,
                options: .storageModeShared
            )!
            b.label = "Uniforms[\(i)]"
            return b
        }

        super.init()
        startMotionTracking()
    }

    func uploadTexture(cgImage: CGImage) {
        let width  = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return }

        let alignment   = 64
        let rawBPR      = width * 4
        let bytesPerRow = (rawBPR + alignment - 1) / alignment * alignment

        guard let mtlBuf = device.makeBuffer(
            length: height * bytesPerRow,
            options: .storageModeShared
        ) else {
            print("[MetalGyroRenderer] makeBuffer failed")
            return
        }

        guard let ctx = CGContext(
            data: mtlBuf.contents(),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            print("[MetalGyroRenderer] CGContext init failed")
            return
        }

        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        td.usage       = .shaderRead
        td.storageMode = .shared

        guard let tex = mtlBuf.makeTexture(
            descriptor: td,
            offset: 0,
            bytesPerRow: bytesPerRow
        ) else {
            print("[MetalGyroRenderer] makeTexture from buffer failed")
            return
        }
        tex.label = "ContentTexture"

        textureLock.lock()
        texture = tex
        textureLock.unlock()
        print("[MetalGyroRenderer] texture ready \(width)x\(height)")
    }


    private func startMotionTracking() {
        guard motionManager.isDeviceMotionAvailable else { return }
        // Balanced update rate: 60Hz (good balance of responsiveness and stability)
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.showsDeviceMovementDisplay = false

        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive

        // Try .xTrueNorthZVertical for better stability, fallback to .xArbitraryZVertical
        let referenceFrame: CMAttitudeReferenceFrame = .xArbitraryZVertical
        
        motionManager.startDeviceMotionUpdates(using: referenceFrame, to: q) {
            [weak self] motion, _ in
            guard let self, let m = motion else { return }

            let currentQ = m.attitude.quaternion

            if self.referenceQuaternion == nil {
                self.referenceQuaternion = currentQ
            }
            guard var refQ = self.referenceQuaternion else { return }

            let invRef = CMQuaternion(x: -refQ.x, y: -refQ.y,
                                      z: -refQ.z, w:  refQ.w)
            let rel = Self.multiplyQ(invRef, currentQ)

            let rawX = -Float(rel.y) * 2.0
            let rawY =  Float(rel.x) * 2.0

            // Apply low-pass filter only if smoothing is enabled
            let stabilizedX: Float
            let stabilizedY: Float
            
            if self.smoothing > 0 {
                let alpha: Float = 0.4
                self.lpX += (rawX - self.lpX) * alpha
                self.lpY += (rawY - self.lpY) * alpha
                stabilizedX = self.lpX
                stabilizedY = self.lpY
            } else {
                // Zero smoothing = instant response, no filtering
                stabilizedX = rawX
                stabilizedY = rawY
            }

            // Restore drift compensation - essential for stable reference frame
            let magnitude = sqrt(rawX*rawX + rawY*rawY)
            let baseDrift: Float = 0.0002
            let edgeBoost: Float = 0.005
            let driftSpeed = baseDrift + edgeBoost * (magnitude / self.maxOffset)
                                                   * (magnitude / self.maxOffset)
            refQ = Self.slerpQ(refQ, currentQ, tx: driftSpeed, ty: driftSpeed)
            self.referenceQuaternion = refQ

            let tx = min(max(stabilizedX, -self.maxOffset), self.maxOffset)
            let ty = min(max(stabilizedY, -self.maxOffset), self.maxOffset)

            // For vehicle vibration: disable Z-axis scaling (keeps it at 1.0 for stability)
            let targetScale: Float = self.smoothing > 0 ? {
                let az = -Float(m.userAcceleration.z)
                let currentScale = self.targetOffset.z
                let newScale = min(max(currentScale + az * 0.02, 0.85), 1.15)
                return newScale + (1.0 - newScale) * 0.02
            }() : 1.0

            self.targetOffset = SIMD3(-tx, -ty, targetScale)
            self.hasNewMotionData = true
        }
    }



    private static func multiplyQ(_ q1: CMQuaternion, _ q2: CMQuaternion) -> CMQuaternion {
        CMQuaternion(
            x: q1.w*q2.x + q1.x*q2.w + q1.y*q2.z - q1.z*q2.y,
            y: q1.w*q2.y - q1.x*q2.z + q1.y*q2.w + q1.z*q2.x,
            z: q1.w*q2.z + q1.x*q2.y - q1.y*q2.x + q1.z*q2.w,
            w: q1.w*q2.w - q1.x*q2.x - q1.y*q2.y - q1.z*q2.z
        )
    }

    private static func slerpQ(_ q1: CMQuaternion, _ q2: CMQuaternion,
                                tx: Float, ty: Float) -> CMQuaternion {
        let t = Double(max(tx, ty))
        var dot = q1.x*q2.x + q1.y*q2.y + q1.z*q2.z + q1.w*q2.w
        var q2 = q2
        if dot < 0 { q2 = CMQuaternion(x:-q2.x,y:-q2.y,z:-q2.z,w:-q2.w); dot = -dot }
        if dot > 0.9995 {
            return CMQuaternion(x: q1.x + t*(q2.x-q1.x), y: q1.y + t*(q2.y-q1.y),
                                z: q1.z + t*(q2.z-q1.z), w: q1.w + t*(q2.w-q1.w))
        }
        let theta0 = acos(dot)
        let theta  = theta0 * t
        let s1 = cos(theta) - dot * sin(theta) / sin(theta0)
        let s2 = sin(theta) / sin(theta0)
        return CMQuaternion(x: s1*q1.x+s2*q2.x, y: s1*q1.y+s2*q2.y,
                            z: s1*q1.z+s2*q2.z, w: s1*q1.w+s2*q2.w)
    }


    func startDisplayLink() {
        let dl = CADisplayLink(target: self, selector: #selector(tick))
        // Match motion sensor rate for stability
        dl.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    @objc private func tick() {
        // Always render if we have new motion data for instant response
        guard hasNewMotionData else { return }
        hasNewMotionData = false

        let target = targetOffset

        // For vehicle vibration cancellation: use smoothing if provided, else instant update
        if smoothing > 0 {
            let deadZone: Float = 0.0005
            let dx = target.x - currentOffset.x
            let dy = target.y - currentOffset.y
            let dz = target.z - currentOffset.z
            guard abs(dx) > deadZone || abs(dy) > deadZone || abs(dz) > deadZone else { return }

            let xySmoothing: Float = smoothing
            let zSmoothing:  Float = smoothing * 0.4

            currentOffset.x += dx * xySmoothing
            currentOffset.y += dy * xySmoothing
            currentOffset.z += dz * zSmoothing
        } else {
            // Zero smoothing = instant response, no interpolation or dead zone
            currentOffset = target
        }
        
        mtkView?.draw()
    }

    func tearDown() {
        displayLink?.invalidate()
        displayLink = nil
        motionManager.stopDeviceMotionUpdates()
    }


    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        frameSemaphore.wait()

        guard
            let drawable   = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor
        else { frameSemaphore.signal(); return }

        textureLock.lock()
        let tex = texture
        textureLock.unlock()

        guard let tex else { frameSemaphore.signal(); return }

        currentBufferIndex = (currentBufferIndex + 1) % MetalGyroRenderer.maxFramesInFlight
        let ubuf = uniformBuffers[currentBufferIndex]
        let sx = quadScale.x * currentOffset.z
        let sy = quadScale.y * currentOffset.z
        ubuf.contents()
            .bindMemory(to: SIMD4<Float>.self, capacity: 1)
            .pointee = SIMD4(currentOffset.x, currentOffset.y, sx, sy)

        guard let cb = commandQueue.makeCommandBuffer() else {
            frameSemaphore.signal(); return
        }
        cb.addCompletedHandler { [weak self] _ in self?.frameSemaphore.signal() }

        guard let enc = cb.makeRenderCommandEncoder(descriptor: descriptor) else {
            frameSemaphore.signal(); return
        }
        enc.setRenderPipelineState(pipelineState)
        enc.setVertexBuffer(quadBuffer, offset: 0, index: 0)
        enc.setVertexBuffer(ubuf,       offset: 0, index: 1)
        enc.setFragmentTexture(tex, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()

        cb.present(drawable)
        cb.commit()
    }
}
