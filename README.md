# LiDAR Point Cloud Visualizer

An iOS app that captures real-time LiDAR depth data and renders it as an interactive 3D point cloud using Metal.

## Features

- **Real-time LiDAR capture** - Uses ARKit's sceneDepth API to capture depth data at 30fps
- **Metal-based rendering** - High-performance point cloud visualization with custom shaders
- **Multiple color modes**:
  - Depth (near=warm, far=cool)
  - Confidence (quality-based coloring)
  - White (monochrome)
  - Rainbow (cycling hue)
- **Interactive camera** - Pan to rotate, pinch to adjust point size
- **Adjustable density** - Control point cloud density for performance tuning

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
5. Use gestures:
   - **Pan**: Rotate the view
   - **Pinch**: Adjust point size
6. Adjust color mode and density in the control panel

## Building

Open `LiDARPointCloud.xcodeproj` in Xcode and run on a physical device (simulator doesn't support LiDAR).

## License

MIT
