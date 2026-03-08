import SwiftUI

struct ContentView: View {
    @StateObject private var sessionManager = ARSessionManager()
    @State private var cameraRotation: SIMD2<Float> = SIMD2<Float>(0.3, 0)
    @State private var pointSize: Float = 6.0
    @State private var showControls = true
    @State private var isFrozen = false
    @State private var showStats = false
    @State private var screenshotFlash = false
    @State private var showExportAlert = false
    @State private var exportedFileURL: URL?

    var body: some View {
        ZStack {
            // Point cloud visualization
            MetalPointCloudView(
                sessionManager: sessionManager,
                cameraRotation: $cameraRotation,
                pointSize: $pointSize
            )
            .ignoresSafeArea()

            // Empty state overlay
            if !sessionManager.isRunning && sessionManager.pointCount == 0 {
                VStack(spacing: 20) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.5))

                    Text("LiDAR Point Cloud")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Tap Start to begin scanning.\nPoint your device at objects to capture.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button(action: { sessionManager.startSession() }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Start Scanning")
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(25)
                    }
                    .padding(.top, 10)
                }
                .padding(40)
            }

            // Screenshot flash effect
            if screenshotFlash {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            // UI Overlay
            VStack {
                // Status bar
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 10, height: 10)
                            Text(statusText)
                                .font(.headline)
                        }
                        Text(pointCountText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Quick action buttons
                    HStack(spacing: 12) {
                        // Stats toggle
                        Button(action: { showStats.toggle() }) {
                            Image(systemName: "chart.bar.fill")
                                .font(.title3)
                                .foregroundColor(showStats ? .blue : .white)
                        }

                        // Screenshot button
                        Button(action: takeScreenshot) {
                            Image(systemName: "camera.fill")
                                .font(.title3)
                        }

                        // Freeze button
                        Button(action: toggleFreeze) {
                            Image(systemName: isFrozen ? "pause.fill" : "playpause.fill")
                                .font(.title3)
                                .foregroundColor(isFrozen ? .orange : .white)
                        }

                        // Settings toggle
                        Button(action: { showControls.toggle() }) {
                            Image(systemName: showControls ? "gearshape.fill" : "gearshape")
                                .font(.title3)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .padding()

                // Stats panel
                if showStats {
                    statsPanel
                }

                Spacer()

                // Controls panel
                if showControls {
                    controlsPanel
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
        .alert("Export Complete", isPresented: $showExportAlert) {
            Button("OK", role: .cancel) { }
            if let url = exportedFileURL {
                ShareLink(item: url) {
                    Text("Share")
                }
            }
        } message: {
            if let url = exportedFileURL {
                Text("Point cloud saved to:\n\(url.lastPathComponent)")
            } else {
                Text("Export failed")
            }
        }
    }

    // MARK: - Subviews

    private var statsPanel: some View {
        HStack(spacing: 20) {
            StatItem(title: "Points", value: formatNumber(sessionManager.pointCount))
            StatItem(title: "Mode", value: sessionManager.colorMode.rawValue)
            StatItem(title: "Density", value: densityLabel)
            StatItem(title: "Size", value: String(format: "%.1f", pointSize))
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var controlsPanel: some View {
        VStack(spacing: 16) {
            // Start/Stop button
            Button(action: {
                if sessionManager.isRunning {
                    sessionManager.stopSession()
                } else {
                    sessionManager.startSession()
                }
                isFrozen = false
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

            // Export button
            Button(action: exportPointCloud) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export PLY")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(sessionManager.pointCount > 0 ? Color.purple.opacity(0.2) : Color.gray.opacity(0.1))
                .foregroundColor(sessionManager.pointCount > 0 ? .purple : .gray)
                .cornerRadius(12)
            }
            .disabled(sessionManager.pointCount == 0)

            // Bottom buttons row
            HStack(spacing: 12) {
                // Reset view button
                Button(action: resetView) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
                }

                // Clear points button
                Button(action: clearPoints) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding()
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        if isFrozen { return .orange }
        return sessionManager.isRunning ? .green : .red
    }

    private var statusText: String {
        if isFrozen { return "Frozen" }
        return sessionManager.isRunning ? "Scanning" : "Stopped"
    }

    private var pointCountText: String {
        let count = sessionManager.pointCount
        if count == 0 { return "No points captured" }
        return "\(formatNumber(count)) points"
    }

    private var densityLabel: String {
        switch sessionManager.subsampleFactor {
        case 1: return "Ultra"
        case 2: return "High"
        case 3: return "Medium"
        default: return "Low"
        }
    }

    // MARK: - Actions

    private func resetView() {
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraRotation = SIMD2<Float>(0.3, 0)
            pointSize = 6.0
        }
    }

    private func clearPoints() {
        sessionManager.clearPoints()
    }

    private func exportPointCloud() {
        if let url = sessionManager.exportToPLY() {
            exportedFileURL = url
            showExportAlert = true
        }
    }

    private func toggleFreeze() {
        isFrozen.toggle()
        if isFrozen {
            sessionManager.pauseUpdates()
        } else {
            sessionManager.resumeUpdates()
        }
    }

    private func takeScreenshot() {
        // Flash effect
        withAnimation(.easeIn(duration: 0.05)) {
            screenshotFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.2)) {
                screenshotFlash = false
            }
        }

        // TODO: Implement actual screenshot saving
        // For now, just visual feedback
    }

    private func formatNumber(_ number: Int) -> String {
        if number >= 1000000 {
            return String(format: "%.1fM", Double(number) / 1000000)
        } else if number >= 1000 {
            return String(format: "%.1fK", Double(number) / 1000)
        }
        return "\(number)"
    }
}

// MARK: - Supporting Views

struct StatItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
