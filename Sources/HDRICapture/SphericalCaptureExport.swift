import CoreGraphics
import CoreImage
import Foundation
import UIKit
import simd

struct SphericalCaptureExportBundle: Identifiable, Equatable {
    let id: UUID
    let directoryURL: URL
    let manifestURL: URL
    let previewURL: URL
    let fileURLs: [URL]
    let coveragePercent: Double
    let createdAt: Date

    var shareURLs: [URL] {
        fileURLs
    }

    var displayDirectoryName: String {
        directoryURL.lastPathComponent
    }

    var displayCoverage: String {
        String(format: "%.1f%%", coveragePercent)
    }
}

struct SphericalCaptureManifest: Codable {
    let schemaVersion: Int
    let sessionID: UUID
    let exportedAt: Date
    let patternName: String
    let preview: SphericalPreviewMetadata
    let targets: [SphericalTargetManifest]
}

struct SphericalPreviewMetadata: Codable {
    let width: Int
    let height: Int
    let fileName: String
    let coveragePercent: Double
}

struct SphericalTargetManifest: Codable {
    let target: SphericalTarget
    let status: String
    let angularErrorDegrees: Double?
    let imageFileName: String?
    let metadataFileName: String?
    let capture: CaptureExportMetadata?
}

final class SphericalCaptureExportWriter {
    private let fileManager: FileManager
    private let ciContext = CIContext()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func writeSessionBundle(for session: SphericalCaptureSession) throws -> SphericalCaptureExportBundle {
        let createdAt = Date()
        let directoryURL = try sphericalCapturesDirectory()
            .appendingPathComponent(session.id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var fileURLs: [URL] = []
        var targetManifests: [SphericalTargetManifest] = []
        var projectionInputs: [ProjectionInput] = []

        for target in session.targets {
            if let capturedTarget = session.capturedTargets[target.id] {
                let imageFileName = "\(target.id).jpg"
                let metadataFileName = "\(target.id).json"
                let imageURL = directoryURL.appendingPathComponent(imageFileName)
                let metadataURL = directoryURL.appendingPathComponent(metadataFileName)

                let image = try cgImage(for: capturedTarget.capture)
                try jpegData(from: image).write(to: imageURL, options: [.atomic])
                let metadata = CaptureExportMetadata(capture: capturedTarget.capture, exportedAt: createdAt)
                try metadataData(metadata).write(to: metadataURL, options: [.atomic])

                fileURLs.append(imageURL)
                fileURLs.append(metadataURL)
                projectionInputs.append(ProjectionInput(capturedTarget: capturedTarget, image: image))
                targetManifests.append(
                    SphericalTargetManifest(
                        target: target,
                        status: "captured",
                        angularErrorDegrees: capturedTarget.angularErrorDegrees,
                        imageFileName: imageFileName,
                        metadataFileName: metadataFileName,
                        capture: metadata
                    )
                )
            } else {
                targetManifests.append(
                    SphericalTargetManifest(
                        target: target,
                        status: "pending",
                        angularErrorDegrees: nil,
                        imageFileName: nil,
                        metadataFileName: nil,
                        capture: nil
                    )
                )
            }
        }

        let previewResult = try SphericalReprojectionPreviewRenderer().render(inputs: projectionInputs)
        let previewURL = directoryURL.appendingPathComponent("preview.jpg")
        try jpegData(from: previewResult.image).write(to: previewURL, options: [.atomic])
        fileURLs.append(previewURL)

        let manifest = SphericalCaptureManifest(
            schemaVersion: 1,
            sessionID: session.id,
            exportedAt: createdAt,
            patternName: "fast-8-single-exposure",
            preview: SphericalPreviewMetadata(
                width: previewResult.width,
                height: previewResult.height,
                fileName: previewURL.lastPathComponent,
                coveragePercent: previewResult.coveragePercent
            ),
            targets: targetManifests
        )
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        try metadataData(manifest).write(to: manifestURL, options: [.atomic])
        fileURLs.append(manifestURL)

        return SphericalCaptureExportBundle(
            id: session.id,
            directoryURL: directoryURL,
            manifestURL: manifestURL,
            previewURL: previewURL,
            fileURLs: fileURLs,
            coveragePercent: previewResult.coveragePercent,
            createdAt: createdAt
        )
    }

    private func sphericalCapturesDirectory() throws -> URL {
        let documentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let capturesURL = documentsURL.appendingPathComponent("SphericalCaptures", isDirectory: true)
        try fileManager.createDirectory(at: capturesURL, withIntermediateDirectories: true)
        return capturesURL
    }

    private func cgImage(for capture: HighResolutionFrameCapture) throws -> CGImage {
        let ciImage = CIImage(cvPixelBuffer: capture.pixelBuffer)
        let extent = CGRect(x: 0, y: 0, width: capture.pixelWidth, height: capture.pixelHeight)
        guard let cgImage = ciContext.createCGImage(ciImage, from: extent) else {
            throw CaptureExportError.imageConversionFailed
        }
        return cgImage
    }

    private func jpegData(from image: CGImage) throws -> Data {
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.9) else {
            throw CaptureExportError.jpegEncodingFailed
        }
        return data
    }

    private func metadataData<T: Encodable>(_ metadata: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(metadata)
    }
}

private struct ProjectionInput {
    let capturedTarget: SphericalCapturedTarget
    let image: CGImage
}

private struct SphericalPreviewResult {
    let image: CGImage
    let width: Int
    let height: Int
    let coveragePercent: Double
}

private final class SphericalReprojectionPreviewRenderer {
    private let width: Int
    private let height: Int

    init(width: Int = 1024, height: Int = 512) {
        self.width = width
        self.height = height
    }

    func render(inputs: [ProjectionInput]) throws -> SphericalPreviewResult {
        guard !inputs.isEmpty else {
            throw SphericalCaptureExportError.noCapturedTargets
        }

        let sources = try inputs.map(SourceImage.init(input:))
        var output = [UInt8](repeating: 0, count: width * height * 4)
        var coveredPixelCount = 0

        for y in 0..<height {
            for x in 0..<width {
                let direction = worldDirectionForEquirectangularPixel(x: x, y: y)
                guard let sample = sample(direction: direction, from: sources) else {
                    continue
                }

                let outputIndex = (y * width + x) * 4
                output[outputIndex] = sample.r
                output[outputIndex + 1] = sample.g
                output[outputIndex + 2] = sample.b
                output[outputIndex + 3] = 255
                coveredPixelCount += 1
            }
        }

        guard let dataProvider = CGDataProvider(data: Data(output) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: dataProvider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              )
        else {
            throw SphericalCaptureExportError.previewEncodingFailed
        }

        let coveragePercent = Double(coveredPixelCount) / Double(width * height) * 100.0
        return SphericalPreviewResult(
            image: image,
            width: width,
            height: height,
            coveragePercent: coveragePercent
        )
    }

    private func worldDirectionForEquirectangularPixel(x: Int, y: Int) -> SIMD3<Float> {
        let u = (Float(x) + 0.5) / Float(width)
        let v = (Float(y) + 0.5) / Float(height)
        let longitude = (u * 2.0 - 1.0) * Float.pi
        let latitude = (0.5 - v) * Float.pi
        let direction = SIMD3<Float>(
            cos(latitude) * sin(longitude),
            sin(latitude),
            -cos(latitude) * cos(longitude)
        )
        return simd_normalize(direction)
    }

    private func sample(direction: SIMD3<Float>, from sources: [SourceImage]) -> PixelSample? {
        var bestSource: SourceProjection?

        for source in sources {
            guard let projection = source.project(worldDirection: direction) else {
                continue
            }
            if bestSource == nil || projection.alignment > bestSource!.alignment {
                bestSource = projection
            }
        }

        return bestSource?.sample
    }
}

private struct SourceProjection {
    let alignment: Float
    let sample: PixelSample
}

private struct PixelSample {
    let r: UInt8
    let g: UInt8
    let b: UInt8
}

private final class SourceImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]
    let cameraToWorld: simd_float4x4
    let worldToCamera: simd_float4x4
    let cameraForward: SIMD3<Float>
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float

    init(input: ProjectionInput) throws {
        let capture = input.capturedTarget.capture
        self.width = input.image.width
        self.height = input.image.height
        self.pixels = try Self.rgbaPixels(from: input.image)
        self.cameraToWorld = try simd_float4x4(columnMajorValues: capture.cameraTransformColumns)
        self.worldToCamera = cameraToWorld.inverse
        self.cameraForward = capture.cameraForwardWorld
        self.fx = capture.cameraIntrinsicsColumns[safe: 0] ?? 0
        self.fy = capture.cameraIntrinsicsColumns[safe: 4] ?? 0
        self.cx = capture.cameraIntrinsicsColumns[safe: 6] ?? 0
        self.cy = capture.cameraIntrinsicsColumns[safe: 7] ?? 0
    }

    func project(worldDirection: SIMD3<Float>) -> SourceProjection? {
        let cameraDirection4 = worldToCamera * SIMD4<Float>(worldDirection.x, worldDirection.y, worldDirection.z, 0)
        let cameraDirection = SIMD3<Float>(cameraDirection4.x, cameraDirection4.y, cameraDirection4.z)
        guard cameraDirection.z < -0.001 else {
            return nil
        }

        let projectedX = fx * (cameraDirection.x / -cameraDirection.z) + cx
        let projectedY = fy * (-cameraDirection.y / -cameraDirection.z) + cy
        guard projectedX >= 0,
              projectedY >= 0,
              projectedX < Float(width),
              projectedY < Float(height)
        else {
            return nil
        }

        let sample = pixelAt(x: Int(projectedX), y: Int(projectedY))
        let alignment = simd_dot(simd_normalize(worldDirection), cameraForward)
        return SourceProjection(alignment: alignment, sample: sample)
    }

    private func pixelAt(x: Int, y: Int) -> PixelSample {
        let index = (y * width + x) * 4
        return PixelSample(r: pixels[index], g: pixels[index + 1], b: pixels[index + 2])
    }

    private static func rgbaPixels(from image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SphericalCaptureExportError.previewEncodingFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
}

enum SphericalCaptureExportError: LocalizedError {
    case noCapturedTargets
    case invalidCameraMetadata
    case previewEncodingFailed

    var errorDescription: String? {
        switch self {
        case .noCapturedTargets:
            return "Capture at least one spherical target before exporting."
        case .invalidCameraMetadata:
            return "A captured target is missing camera transform or intrinsics metadata."
        case .previewEncodingFailed:
            return "Could not generate the spherical preview image."
        }
    }
}

private extension simd_float4x4 {
    init(columnMajorValues values: [Float]) throws {
        guard values.count >= 16 else {
            throw SphericalCaptureExportError.invalidCameraMetadata
        }
        self.init(
            SIMD4<Float>(values[0], values[1], values[2], values[3]),
            SIMD4<Float>(values[4], values[5], values[6], values[7]),
            SIMD4<Float>(values[8], values[9], values[10], values[11]),
            SIMD4<Float>(values[12], values[13], values[14], values[15])
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
