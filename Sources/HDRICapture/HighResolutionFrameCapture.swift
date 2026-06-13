import ARKit
import AVFoundation
import CoreVideo
import Foundation
import simd

enum HighResolutionCaptureState: Equatable {
    case idle
    case capturing
    case succeeded
    case failed(String)
    case unsupported(String)

    var displayName: String {
        switch self {
        case .idle:
            return "Ready"
        case .capturing:
            return "Capturing"
        case .succeeded:
            return "Captured"
        case .failed(let message):
            return "Failed: \(message)"
        case .unsupported(let message):
            return "Unsupported: \(message)"
        }
    }

    var isCapturing: Bool {
        if case .capturing = self {
            return true
        }
        return false
    }

    var isUnsupported: Bool {
        if case .unsupported = self {
            return true
        }
        return false
    }
}

struct HighResolutionVideoFormatSnapshot: Codable, Equatable {
    let imageWidth: Int
    let imageHeight: Int
    let framesPerSecond: Int
    let captureDevicePosition: String
    let captureDeviceType: String
    let isRecommendedForHighResolutionFrameCapturing: Bool
    let isVideoHDRSupported: Bool

    init(format: ARConfiguration.VideoFormat) {
        imageWidth = Int(format.imageResolution.width.rounded())
        imageHeight = Int(format.imageResolution.height.rounded())
        framesPerSecond = format.framesPerSecond
        captureDevicePosition = format.captureDevicePosition.displayName
        captureDeviceType = format.captureDeviceType.displayName
        isRecommendedForHighResolutionFrameCapturing = format.isRecommendedForHighResolutionFrameCapturing
        isVideoHDRSupported = format.isVideoHDRSupported
    }

    var displayResolution: String {
        "\(imageWidth)x\(imageHeight)"
    }

    var displayName: String {
        "\(displayResolution) @ \(framesPerSecond) fps"
    }

    var isBackUltraWide: Bool {
        captureDevicePosition == AVCaptureDevice.Position.back.displayName
            && captureDeviceType == AVCaptureDevice.DeviceType.builtInUltraWideCamera.displayName
    }
}

final class HighResolutionFrameCapture: Identifiable {
    let id = UUID()
    let capturedAt: Date
    let pixelBuffer: CVPixelBuffer
    let timestamp: TimeInterval
    let pixelWidth: Int
    let pixelHeight: Int
    let pixelFormat: String
    let planeCount: Int
    let trackingState: String
    let exposureDuration: TimeInterval
    let exposureOffset: Float
    let cameraTransformColumns: [Float]
    let cameraIntrinsicsColumns: [Float]
    let streamingVideoFormat: HighResolutionVideoFormatSnapshot?

    init(frame: ARFrame, streamingVideoFormat: HighResolutionVideoFormatSnapshot?) {
        let pixelBuffer = frame.capturedImage
        self.capturedAt = Date()
        self.pixelBuffer = pixelBuffer
        self.timestamp = frame.timestamp
        self.pixelWidth = CVPixelBufferGetWidth(pixelBuffer)
        self.pixelHeight = CVPixelBufferGetHeight(pixelBuffer)
        self.pixelFormat = Self.pixelFormatName(CVPixelBufferGetPixelFormatType(pixelBuffer))
        self.planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
        self.trackingState = frame.camera.trackingState.displayName
        self.exposureDuration = frame.camera.exposureDuration
        self.exposureOffset = frame.camera.exposureOffset
        self.cameraTransformColumns = Self.flatten(frame.camera.transform)
        self.cameraIntrinsicsColumns = Self.flatten(frame.camera.intrinsics)
        self.streamingVideoFormat = streamingVideoFormat
    }

    var displayResolution: String {
        "\(pixelWidth)x\(pixelHeight)"
    }

    var displayTimestamp: String {
        String(format: "%.2f", timestamp)
    }

    var displayExposureDuration: String {
        guard exposureDuration > 0 else {
            return "Unknown"
        }
        return String(format: "%.5f s", exposureDuration)
    }

    var displayExposureOffset: String {
        String(format: "%.2f EV", exposureOffset)
    }

    var displayCameraTranslation: String {
        guard cameraTransformColumns.count >= 16 else {
            return "Unavailable"
        }
        return String(
            format: "x %.3f, y %.3f, z %.3f m",
            cameraTransformColumns[12],
            cameraTransformColumns[13],
            cameraTransformColumns[14]
        )
    }

    var displayIntrinsics: String {
        guard cameraIntrinsicsColumns.count >= 9 else {
            return "Unavailable"
        }
        return String(
            format: "fx %.1f, fy %.1f, cx %.1f, cy %.1f",
            cameraIntrinsicsColumns[0],
            cameraIntrinsicsColumns[4],
            cameraIntrinsicsColumns[6],
            cameraIntrinsicsColumns[7]
        )
    }

    private static func flatten(_ matrix: simd_float4x4) -> [Float] {
        [
            matrix.columns.0.x,
            matrix.columns.0.y,
            matrix.columns.0.z,
            matrix.columns.0.w,
            matrix.columns.1.x,
            matrix.columns.1.y,
            matrix.columns.1.z,
            matrix.columns.1.w,
            matrix.columns.2.x,
            matrix.columns.2.y,
            matrix.columns.2.z,
            matrix.columns.2.w,
            matrix.columns.3.x,
            matrix.columns.3.y,
            matrix.columns.3.z,
            matrix.columns.3.w
        ]
    }

    private static func flatten(_ matrix: simd_float3x3) -> [Float] {
        [
            matrix.columns.0.x,
            matrix.columns.0.y,
            matrix.columns.0.z,
            matrix.columns.1.x,
            matrix.columns.1.y,
            matrix.columns.1.z,
            matrix.columns.2.x,
            matrix.columns.2.y,
            matrix.columns.2.z
        ]
    }

    private static func pixelFormatName(_ pixelFormat: OSType) -> String {
        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            return "420YpCbCr8BiPlanarFullRange"
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            return "420YpCbCr8BiPlanarVideoRange"
        case kCVPixelFormatType_32BGRA:
            return "32BGRA"
        default:
            let bytes: [UInt8] = [
                UInt8((pixelFormat >> 24) & 0xff),
                UInt8((pixelFormat >> 16) & 0xff),
                UInt8((pixelFormat >> 8) & 0xff),
                UInt8(pixelFormat & 0xff)
            ]
            let fourCC = String(bytes: bytes, encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let fourCC, !fourCC.isEmpty {
                return "\(fourCC) (\(pixelFormat))"
            }
            return "Pixel format \(pixelFormat)"
        }
    }
}

extension ARCamera.TrackingState {
    var displayName: String {
        switch self {
        case .notAvailable:
            return "Not available"
        case .normal:
            return "Normal"
        case .limited(let reason):
            return "Limited: \(reason.displayName)"
        }
    }
}

private extension ARCamera.TrackingState.Reason {
    var displayName: String {
        switch self {
        case .initializing:
            return "initializing"
        case .excessiveMotion:
            return "excessive motion"
        case .insufficientFeatures:
            return "insufficient features"
        case .relocalizing:
            return "relocalizing"
        @unknown default:
            return "unknown"
        }
    }
}

private extension AVCaptureDevice.Position {
    var displayName: String {
        switch self {
        case .unspecified:
            return "Unspecified"
        case .back:
            return "Back"
        case .front:
            return "Front"
        @unknown default:
            return "Unknown (\(rawValue))"
        }
    }
}

private extension AVCaptureDevice.DeviceType {
    var displayName: String {
        rawValue
            .replacingOccurrences(of: "com.apple.avfoundation.avcapturedevice.built-in_", with: "")
            .replacingOccurrences(of: "com.apple.avfoundation.avcapturedevice.", with: "")
    }
}
