import ARKit
import Combine

/// Manages the ARKit session and extracts depth data from LiDAR
class ARSessionManager: NSObject, ObservableObject {
    let session = ARSession()

    @Published var pointCloud: [SIMD3<Float>] = []
    @Published var pointColors: [SIMD3<Float>] = []
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var pointCount: Int = 0

    // Settings
    @Published var colorMode: ColorMode = .depth
    @Published var maxPoints: Int = 50000
    @Published var subsampleFactor: Int = 2  // Sample every Nth pixel

    enum ColorMode: String, CaseIterable {
        case depth = "Depth"
        case confidence = "Confidence"
        case white = "White"
        case rainbow = "Rainbow"
    }

    private var lastUpdateTime: TimeInterval = 0
    private let updateInterval: TimeInterval = 1.0 / 30.0  // 30 FPS max
    private var isPaused = false

    override init() {
        super.init()
        session.delegate = self
    }

    func startSession() {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            errorMessage = "LiDAR not available on this device"
            return
        }

        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]

        session.run(config)
        isRunning = true
        errorMessage = nil
    }

    func stopSession() {
        session.pause()
        isRunning = false
    }

    func pauseUpdates() {
        isPaused = true
    }

    func resumeUpdates() {
        isPaused = false
    }

    func clearPoints() {
        pointCloud = []
        pointColors = []
        pointCount = 0
    }

    /// Export point cloud to PLY format
    /// Returns the file URL if successful
    func exportToPLY() -> URL? {
        guard !pointCloud.isEmpty else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "pointcloud_\(dateFormatter.string(from: Date())).ply"

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)

        var plyContent = """
        ply
        format ascii 1.0
        element vertex \(pointCloud.count)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header

        """

        for i in 0..<pointCloud.count {
            let point = pointCloud[i]
            let color = pointColors[i]

            let r = UInt8(min(max(color.x * 255, 0), 255))
            let g = UInt8(min(max(color.y * 255, 0), 255))
            let b = UInt8(min(max(color.z * 255, 0), 255))

            plyContent += "\(point.x) \(point.y) \(point.z) \(r) \(g) \(b)\n"
        }

        do {
            try plyContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("Failed to export PLY: \(error)")
            return nil
        }
    }

    /// Convert depth buffer to 3D point cloud
    private func processDepthFrame(_ frame: ARFrame) {
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }

        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(confidenceMap!, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(confidenceMap!, .readOnly)
        }

        guard let depthPointer = CVPixelBufferGetBaseAddress(depthMap)?.assumingMemoryBound(to: Float32.self),
              let confidencePointer = CVPixelBufferGetBaseAddress(confidenceMap!)?.assumingMemoryBound(to: UInt8.self) else {
            return
        }

        // Get camera intrinsics for depth-to-3D conversion
        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]

        // Scale factors (depth map may be different resolution than intrinsics)
        let scaleX = Float(width) / Float(frame.camera.imageResolution.width)
        let scaleY = Float(height) / Float(frame.camera.imageResolution.height)

        var newPoints: [SIMD3<Float>] = []
        var newColors: [SIMD3<Float>] = []
        newPoints.reserveCapacity(maxPoints)
        newColors.reserveCapacity(maxPoints)

        let cameraTransform = frame.camera.transform

        // Subsample to reduce point count
        for y in stride(from: 0, to: height, by: subsampleFactor) {
            for x in stride(from: 0, to: width, by: subsampleFactor) {
                let index = y * width + x
                let depth = depthPointer[index]
                let confidence = confidencePointer[index]

                // Filter by depth range and confidence
                guard depth > 0.1 && depth < 5.0 && confidence >= 1 else { continue }

                // Convert from depth image coordinates to 3D camera space
                let xCam = (Float(x) / scaleX - cx) * depth / fx
                let yCam = (Float(y) / scaleY - cy) * depth / fy
                let zCam = -depth  // Negative because camera looks down -Z

                // Transform to world space
                let pointCam = SIMD4<Float>(xCam, -yCam, zCam, 1.0)  // Flip Y
                let pointWorld = cameraTransform * pointCam

                newPoints.append(SIMD3<Float>(pointWorld.x, pointWorld.y, pointWorld.z))

                // Calculate color based on mode
                let color = calculateColor(depth: depth, confidence: confidence, maxDepth: 5.0)
                newColors.append(color)

                if newPoints.count >= maxPoints { break }
            }
            if newPoints.count >= maxPoints { break }
        }

        DispatchQueue.main.async {
            self.pointCloud = newPoints
            self.pointColors = newColors
            self.pointCount = newPoints.count
        }
    }

    private func calculateColor(depth: Float, confidence: UInt8, maxDepth: Float) -> SIMD3<Float> {
        switch colorMode {
        case .depth:
            // Color by depth: near = red/yellow, far = blue/purple
            let t = min(depth / maxDepth, 1.0)
            return hsvToRgb(h: (1.0 - t) * 0.7, s: 1.0, v: 1.0)

        case .confidence:
            // Color by confidence: low = red, medium = yellow, high = green
            let conf = Float(confidence) / 2.0
            return SIMD3<Float>(1.0 - conf, conf, 0.0)

        case .white:
            return SIMD3<Float>(1.0, 1.0, 1.0)

        case .rainbow:
            // Cycle through rainbow based on depth
            let t = (depth / maxDepth).truncatingRemainder(dividingBy: 1.0)
            return hsvToRgb(h: t, s: 1.0, v: 1.0)
        }
    }

    private func hsvToRgb(h: Float, s: Float, v: Float) -> SIMD3<Float> {
        let c = v * s
        let x = c * (1.0 - abs((h * 6.0).truncatingRemainder(dividingBy: 2.0) - 1.0))
        let m = v - c

        var r: Float = 0, g: Float = 0, b: Float = 0
        let hPrime = h * 6.0

        if hPrime < 1 { r = c; g = x; b = 0 }
        else if hPrime < 2 { r = x; g = c; b = 0 }
        else if hPrime < 3 { r = 0; g = c; b = x }
        else if hPrime < 4 { r = 0; g = x; b = c }
        else if hPrime < 5 { r = x; g = 0; b = c }
        else { r = c; g = 0; b = x }

        return SIMD3<Float>(r + m, g + m, b + m)
    }
}

extension ARSessionManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !isPaused else { return }

        let currentTime = frame.timestamp
        guard currentTime - lastUpdateTime >= updateInterval else { return }
        lastUpdateTime = currentTime

        processDepthFrame(frame)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
            self.isRunning = false
        }
    }
}
