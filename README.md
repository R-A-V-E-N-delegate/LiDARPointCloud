# LiDAR Point Cloud Visualizer

An iOS app that captures real-time LiDAR depth data and renders it as an interactive 3D point cloud using Metal.

## Features

### Core
- **Real-time LiDAR capture** - Uses ARKit's sceneDepth API to capture depth data at 30fps
- **Metal-based rendering** - High-performance point cloud visualization with custom shaders
- **Multiple color modes**:
  - Depth (near=warm, far=cool)
  - Confidence (quality-based coloring)
  - White (monochrome)
  - Rainbow (cycling hue)
- **Adjustable density** - Control point cloud density for performance tuning

### Interaction
- **Pan** - Rotate the view
- **Pinch** - Adjust point size
- **Double-tap** - Reset camera to default position (with haptic feedback)
- **Freeze** - Pause point cloud updates to inspect current capture

### Export
- **PLY export** - Save point cloud to PLY format with RGB colors
- **Share** - Share exported files via iOS share sheet

## Requirements

- iOS 17.0+
- Device with LiDAR scanner (iPhone 12 Pro and later, iPad Pro 2020 and later)

## Technical Details

### Architecture

```
┌─────────────────────┐     ┌──────────────────────┐
│   ARSessionManager  │────▶│  PointCloudRenderer  │
│  (ARKit depth data) │     │    (Metal drawing)   │
└─────────────────────┘     └──────────────────────┘
         │                            │
         ▼                            ▼
┌─────────────────────┐     ┌──────────────────────┐
│  Depth → 3D Points  │     │   Shaders.metal      │
│  (camera intrinsics)│     │   (vertex/fragment)  │
└─────────────────────┘     └──────────────────────┘
```

### Depth to 3D Conversion

Each pixel in the depth buffer is converted to a 3D world-space point using:

1. Camera intrinsics (focal length, principal point)
2. Depth value at pixel
3. Camera transform (world position/orientation)

```swift
// Camera space
let xCam = (pixelX - cx) * depth / fx
let yCam = (pixelY - cy) * depth / fy
let zCam = -depth

// World space
let pointWorld = cameraTransform * SIMD4(xCam, -yCam, zCam, 1.0)
```

## Usage

1. Open the app on a LiDAR-equipped device
2. Grant camera access when prompted
3. Tap **Start** to begin scanning
4. Point the camera at objects to capture the point cloud
5. Use gestures to navigate:
   - **Pan**: Rotate the view
   - **Pinch**: Adjust point size
   - **Double-tap**: Reset view
6. Use the control panel to:
   - Change color mode
   - Adjust point density
   - Freeze/resume scanning
   - Export to PLY
   - Clear captured points

## Building

Open `LiDARPointCloud.xcodeproj` in Xcode and run on a physical device (simulator doesn't support LiDAR).

## Files

- `ARSessionManager.swift` - ARKit session, depth extraction, PLY export
- `PointCloudRenderer.swift` - Metal renderer with camera controls
- `Shaders.metal` - Vertex and fragment shaders for point rendering
- `ARViewContainer.swift` - SwiftUI wrapper for Metal view with gestures
- `ContentView.swift` - Main UI with controls and stats

## License

MIT
