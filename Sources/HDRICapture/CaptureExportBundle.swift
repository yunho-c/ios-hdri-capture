import CoreImage
import Foundation
import UIKit

enum CaptureExportState {
    case idle
    case exporting
    case exported
    case failed(String)

    var displayName: String {
        switch self {
        case .idle:
            return "Ready"
        case .exporting:
            return "Exporting"
        case .exported:
            return "Exported"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }

    var isExporting: Bool {
        if case .exporting = self {
            return true
        }
        return false
    }
}

struct CaptureExportBundle: Identifiable, Equatable {
    let id: UUID
    let directoryURL: URL
    let imageURL: URL
    let metadataURL: URL
    let createdAt: Date

    var shareURLs: [URL] {
        [imageURL, metadataURL]
    }

    var displayDirectoryName: String {
        directoryURL.lastPathComponent
    }

    var displayFileNames: String {
        "\(imageURL.lastPathComponent), \(metadataURL.lastPathComponent)"
    }
}

struct CaptureExportMetadata: Codable {
    let schemaVersion: Int
    let captureID: UUID
    let exportedAt: Date
    let capturedAt: Date
    let timestamp: TimeInterval
    let image: CaptureImageMetadata
    let arCamera: CaptureARCameraMetadata
    let streamingVideoFormat: HighResolutionVideoFormatSnapshot?

    init(capture: HighResolutionFrameCapture, exportedAt: Date) {
        self.schemaVersion = 1
        self.captureID = capture.id
        self.exportedAt = exportedAt
        self.capturedAt = capture.capturedAt
        self.timestamp = capture.timestamp
        self.image = CaptureImageMetadata(capture: capture)
        self.arCamera = CaptureARCameraMetadata(capture: capture)
        self.streamingVideoFormat = capture.streamingVideoFormat
    }
}

struct CaptureImageMetadata: Codable {
    let width: Int
    let height: Int
    let pixelFormat: String
    let planeCount: Int

    init(capture: HighResolutionFrameCapture) {
        self.width = capture.pixelWidth
        self.height = capture.pixelHeight
        self.pixelFormat = capture.pixelFormat
        self.planeCount = capture.planeCount
    }
}

struct CaptureARCameraMetadata: Codable {
    let trackingState: String
    let exposureDurationSeconds: TimeInterval
    let exposureOffsetEV: Float
    let transformColumns: [Float]
    let intrinsicsColumns: [Float]

    init(capture: HighResolutionFrameCapture) {
        self.trackingState = capture.trackingState
        self.exposureDurationSeconds = capture.exposureDuration
        self.exposureOffsetEV = capture.exposureOffset
        self.transformColumns = capture.cameraTransformColumns
        self.intrinsicsColumns = capture.cameraIntrinsicsColumns
    }
}

final class CaptureExportWriter {
    private let fileManager: FileManager
    private let ciContext = CIContext()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func writeDebugBundle(for capture: HighResolutionFrameCapture) throws -> CaptureExportBundle {
        let createdAt = Date()
        let directoryURL = try capturesDirectory()
            .appendingPathComponent(capture.id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let imageURL = directoryURL.appendingPathComponent("image.jpg")
        let metadataURL = directoryURL.appendingPathComponent("metadata.json")

        try jpegData(for: capture).write(to: imageURL, options: [.atomic])
        try metadataData(for: capture, exportedAt: createdAt).write(to: metadataURL, options: [.atomic])

        return CaptureExportBundle(
            id: capture.id,
            directoryURL: directoryURL,
            imageURL: imageURL,
            metadataURL: metadataURL,
            createdAt: createdAt
        )
    }

    private func capturesDirectory() throws -> URL {
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let capturesURL = documentsURL.appendingPathComponent("Captures", isDirectory: true)
        try fileManager.createDirectory(at: capturesURL, withIntermediateDirectories: true)
        return capturesURL
    }

    private func jpegData(for capture: HighResolutionFrameCapture) throws -> Data {
        let ciImage = CIImage(cvPixelBuffer: capture.pixelBuffer)
        let extent = CGRect(x: 0, y: 0, width: capture.pixelWidth, height: capture.pixelHeight)
        guard let cgImage = ciContext.createCGImage(ciImage, from: extent) else {
            throw CaptureExportError.imageConversionFailed
        }
        guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.95) else {
            throw CaptureExportError.jpegEncodingFailed
        }
        return data
    }

    private func metadataData(for capture: HighResolutionFrameCapture, exportedAt: Date) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(CaptureExportMetadata(capture: capture, exportedAt: exportedAt))
    }
}

enum CaptureExportError: LocalizedError {
    case imageConversionFailed
    case jpegEncodingFailed
    case missingCapture

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Could not convert the captured pixel buffer into a CGImage."
        case .jpegEncodingFailed:
            return "Could not encode the captured image as JPEG."
        case .missingCapture:
            return "Capture a high-resolution frame before exporting."
        }
    }
}
