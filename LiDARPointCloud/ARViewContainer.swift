import SwiftUI
import MetalKit

/// SwiftUI wrapper for the Metal point cloud view
struct MetalPointCloudView: UIViewRepresentable {
    @ObservedObject var sessionManager: ARSessionManager
    @Binding var cameraRotation: SIMD2<Float>
    @Binding var pointSize: Float

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = 60

        if let renderer = PointCloudRenderer(mtkView: mtkView) {
            context.coordinator.renderer = renderer
            mtkView.delegate = renderer
        }

        // Add gesture recognizers
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        mtkView.addGestureRecognizer(panGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        mtkView.addGestureRecognizer(pinchGesture)

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer?.updatePointCloud(
            points: sessionManager.pointCloud,
            colors: sessionManager.pointColors
        )
        context.coordinator.renderer?.cameraRotation = cameraRotation
        context.coordinator.renderer?.pointSize = pointSize
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: MetalPointCloudView
        var renderer: PointCloudRenderer?

        init(_ parent: MetalPointCloudView) {
            self.parent = parent
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let sensitivity: Float = 0.005

            parent.cameraRotation.y += Float(translation.x) * sensitivity
            parent.cameraRotation.x += Float(translation.y) * sensitivity

            // Clamp pitch
            parent.cameraRotation.x = max(-Float.pi / 2 + 0.1, min(Float.pi / 2 - 0.1, parent.cameraRotation.x))

            gesture.setTranslation(.zero, in: gesture.view)
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .changed {
                let scale = Float(gesture.scale)
                parent.pointSize *= scale
                parent.pointSize = max(1.0, min(20.0, parent.pointSize))
                gesture.scale = 1.0
            }
        }
    }
}
