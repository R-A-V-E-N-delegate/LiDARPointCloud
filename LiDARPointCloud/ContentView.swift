import SwiftUI

struct ContentView: View {
    @StateObject private var sessionManager = ARSessionManager()
    @State private var cameraRotation: SIMD2<Float> = SIMD2<Float>(0.3, 0)
    @State private var pointSize: Float = 6.0
    @State private var showControls = true

    var body: some View {
        ZStack {
            // Point cloud visualization
            MetalPointCloudView(
                sessionManager: sessionManager,
                cameraRotation: $cameraRotation,
                pointSize: $pointSize
            )
            .ignoresSafeArea()

            // UI Overlay
            VStack {
                // Status bar
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(sessionManager.isRunning ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                            Text(sessionManager.isRunning ? "Scanning" : "Stopped")
                                .font(.headline)
                        }
                        Text("\(sessionManager.pointCount) points")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: { showControls.toggle() }) {
                        Image(systemName: showControls ? "gearshape.fill" : "gearshape")
                            .font(.title2)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .padding()

                Spacer()

                // Controls panel
                if showControls {
                    VStack(spacing: 16) {
                        // Start/Stop button
                        Button(action: {
                            if sessionManager.isRunning {
                                sessionManager.stopSession()
                            } else {
                                sessionManager.startSession()
                            }
                        }) {
                            HStack {
                                Image(systemName: sessionManager.isRunning ? "stop.fill" : "play.fill")
                                Text(sessionManager.isRunning ? "Stop" : "Start")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(sessionManager.isRunning ? Color.red : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }

                        // Color mode picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Color Mode")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("Color", selection: $sessionManager.colorMode) {
                                ForEach(ARSessionManager.ColorMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // Point size slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Point Size")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.1f", pointSize))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $pointSize, in: 1...20)
                        }

                        // Density slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Density")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(densityLabel)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: Binding(
                                get: { Double(5 - sessionManager.subsampleFactor) },
                                set: { sessionManager.subsampleFactor = 5 - Int($0) }
                            ), in: 1...4, step: 1)
                        }

                        // Reset view button
                        Button(action: resetView) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset View")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .padding()
                }
            }

            // Error overlay
            if let error = sessionManager.errorMessage {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(error)
                            .font(.callout)
                    }
                    .padding()
                    .background(Color.red.opacity(0.9))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var densityLabel: String {
        switch sessionManager.subsampleFactor {
        case 1: return "Ultra"
        case 2: return "High"
        case 3: return "Medium"
        default: return "Low"
        }
    }

    private func resetView() {
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraRotation = SIMD2<Float>(0.3, 0)
            pointSize = 6.0
        }
    }
}

#Preview {
    ContentView()
}
