import MetalKit
import simd

/// Metal-based renderer for point cloud visualization
class PointCloudRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState

    private var pointBuffer: MTLBuffer?
    private var colorBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?

    private var pointCount: Int = 0

    // Camera properties
    var cameraPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 2)
    var cameraRotation: SIMD2<Float> = SIMD2<Float>(0, 0)  // pitch, yaw
    var pointSize: Float = 4.0

    struct Uniforms {
        var projectionMatrix: simd_float4x4
        var viewMatrix: simd_float4x4
        var pointSize: Float
        var padding: SIMD3<Float> = .zero
    }

    init?(mtkView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return nil
        }

        self.device = device
        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1.0)

        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        // Create pipeline
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "vertexShader"),
              let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
            print("Failed to create shader functions")
            return nil
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat

        // Enable blending for point anti-aliasing
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
            return nil
        }

        // Depth stencil state
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            return nil
        }
        self.depthStencilState = depthState

        // Uniform buffer
        uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.stride, options: .storageModeShared)

        super.init()
    }

    func updatePointCloud(points: [SIMD3<Float>], colors: [SIMD3<Float>]) {
        guard !points.isEmpty else {
            pointCount = 0
            return
        }

        pointCount = points.count

        // Create/update point buffer
        let pointDataSize = points.count * MemoryLayout<SIMD3<Float>>.stride
        if pointBuffer == nil || pointBuffer!.length < pointDataSize {
            pointBuffer = device.makeBuffer(length: pointDataSize, options: .storageModeShared)
        }
        pointBuffer?.contents().copyMemory(from: points, byteCount: pointDataSize)

        // Create/update color buffer
        let colorDataSize = colors.count * MemoryLayout<SIMD3<Float>>.stride
        if colorBuffer == nil || colorBuffer!.length < colorDataSize {
            colorBuffer = device.makeBuffer(length: colorDataSize, options: .storageModeShared)
        }
        colorBuffer?.contents().copyMemory(from: colors, byteCount: colorDataSize)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in mtkView: MTKView) {
        guard pointCount > 0,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let descriptor = mtkView.currentRenderPassDescriptor,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        // Update uniforms
        let aspect = Float(mtkView.drawableSize.width / mtkView.drawableSize.height)
        let projection = perspectiveMatrix(fovY: Float.pi / 3, aspect: aspect, near: 0.01, far: 100)
        let viewMatrix = lookAtMatrix()

        var uniforms = Uniforms(
            projectionMatrix: projection,
            viewMatrix: viewMatrix,
            pointSize: pointSize
        )
        uniformBuffer?.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout<Uniforms>.stride)

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthStencilState)

        encoder.setVertexBuffer(pointBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(colorBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 2)

        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: pointCount)

        encoder.endEncoding()

        if let drawable = mtkView.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }

    private func lookAtMatrix() -> simd_float4x4 {
        // Calculate camera position based on rotation
        let pitch = cameraRotation.x
        let yaw = cameraRotation.y

        let distance: Float = 2.0
        let x = distance * cos(pitch) * sin(yaw)
        let y = distance * sin(pitch)
        let z = distance * cos(pitch) * cos(yaw)

        let eye = SIMD3<Float>(x, y, z)
        let center = SIMD3<Float>(0, 0, 0)
        let up = SIMD3<Float>(0, 1, 0)

        return lookAt(eye: eye, center: center, up: up)
    }

    private func perspectiveMatrix(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let yScale = 1 / tan(fovY * 0.5)
        let xScale = yScale / aspect
        let zRange = far - near

        return simd_float4x4(columns: (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, -(far + near) / zRange, -1),
            SIMD4<Float>(0, 0, -2 * far * near / zRange, 0)
        ))
    }

    private func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = normalize(eye - center)
        let x = normalize(cross(up, z))
        let y = cross(z, x)

        return simd_float4x4(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        ))
    }
}
