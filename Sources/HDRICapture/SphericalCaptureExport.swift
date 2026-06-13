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
    let previewWidth: Int
    let previewHeight: Int
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

    var displayPreviewResolution: String {
        "\(previewWidth)x\(previewHeight)"
    }
}

struct SphericalCaptureManifest: Codable {
    let schemaVersion: Int
    let sessionID: UUID
    let exportedAt: Date
    let patternID: String
    let patternName: String
    let preview: SphericalPreviewMetadata
    let diagnostics: SphericalDiagnosticsMetadata
    let fallbackSources: [SphericalFallbackManifest]
    let targets: [SphericalTargetManifest]
}

struct SphericalPreviewMetadata: Codable {
    let width: Int
    let height: Int
    let fileName: String
    let coveragePercent: Double
}

struct SphericalDiagnosticsMetadata: Codable {
    let coverageMaskFileName: String
    let targetIndexFileName: String
    let fallbackPreviewFileName: String?
    let previewWithFallbackFileName: String?
    let targetIndexWithFallbackFileName: String?
}

struct SphericalFallbackManifest: Codable {
    let role: String
    let imageFileName: String
    let metadataFileName: String
    let previewFileName: String
    let videoFormat: HighResolutionVideoFormatSnapshot
    let capture: CaptureExportMetadata
}

struct SphericalTargetManifest: Codable {
    let target: SphericalTarget
    let status: String
    let angularErrorDegrees: Double?
    let coverageContributionPercent: Double?
    let coveredPixelContributionPercent: Double?
    let debugColorHex: String?
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
        var targetManifestsByID: [String: SphericalTargetManifest] = [:]
        var projectionInputs: [ProjectionInput] = []
        var fallbackInput: ProjectionInput?
        var fallbackManifests: [SphericalFallbackManifest] = []

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
                targetManifestsByID[target.id] = SphericalTargetManifest(
                    target: target,
                    status: "captured",
                    angularErrorDegrees: capturedTarget.angularErrorDegrees,
                    coverageContributionPercent: nil,
                    coveredPixelContributionPercent: nil,
                    debugColorHex: nil,
                    imageFileName: imageFileName,
                    metadataFileName: metadataFileName,
                    capture: metadata
                )
            } else {
                targetManifestsByID[target.id] = SphericalTargetManifest(
                    target: target,
                    status: "pending",
                    angularErrorDegrees: nil,
                    coverageContributionPercent: nil,
                    coveredPixelContributionPercent: nil,
                    debugColorHex: nil,
                    imageFileName: nil,
                    metadataFileName: nil,
                    capture: nil
                )
            }
        }

        if let fallbackCapture = session.fallbackCapture {
            let fallbackDirectoryURL = directoryURL.appendingPathComponent("fallback", isDirectory: true)
            try fileManager.createDirectory(at: fallbackDirectoryURL, withIntermediateDirectories: true)

            let imageFileName = "fallback/ultra-wide.jpg"
            let metadataFileName = "fallback/ultra-wide.json"
            let fallbackPreviewFileName = "fallback-preview.jpg"
            let imageURL = directoryURL.appendingPathComponent(imageFileName)
            let metadataURL = directoryURL.appendingPathComponent(metadataFileName)

            let image = try cgImage(for: fallbackCapture.capture)
            try jpegData(from: image).write(to: imageURL, options: [.atomic])
            let metadata = CaptureExportMetadata(capture: fallbackCapture.capture, exportedAt: createdAt)
            try metadataData(metadata).write(to: metadataURL, options: [.atomic])

            fileURLs.append(imageURL)
            fileURLs.append(metadataURL)

            let input = ProjectionInput(fallbackCapture: fallbackCapture, image: image)
            fallbackInput = input
            let fallbackPreviewResult = try SphericalReprojectionPreviewRenderer().render(inputs: [input])
            let fallbackPreviewURL = directoryURL.appendingPathComponent(fallbackPreviewFileName)
            try jpegData(from: fallbackPreviewResult.image).write(to: fallbackPreviewURL, options: [.atomic])
            fileURLs.append(fallbackPreviewURL)

            fallbackManifests.append(
                SphericalFallbackManifest(
                    role: fallbackCapture.role,
                    imageFileName: imageFileName,
                    metadataFileName: metadataFileName,
                    previewFileName: fallbackPreviewFileName,
                    videoFormat: fallbackCapture.videoFormat,
                    capture: metadata
                )
            )
        }

        let previewResult = try SphericalReprojectionPreviewRenderer().render(inputs: projectionInputs)
        let previewURL = directoryURL.appendingPathComponent("preview.jpg")
        try jpegData(from: previewResult.image).write(to: previewURL, options: [.atomic])
        fileURLs.append(previewURL)

        let coverageMaskURL = directoryURL.appendingPathComponent("coverage-mask.png")
        try pngData(from: previewResult.coverageMaskImage).write(to: coverageMaskURL, options: [.atomic])
        fileURLs.append(coverageMaskURL)

        let targetIndexURL = directoryURL.appendingPathComponent("target-index.png")
        try pngData(from: previewResult.targetIndexImage).write(to: targetIndexURL, options: [.atomic])
        fileURLs.append(targetIndexURL)

        var previewWithFallbackFileName: String?
        var targetIndexWithFallbackFileName: String?
        if let fallbackInput {
            let withFallbackResult = try SphericalReprojectionPreviewRenderer().render(
                inputs: projectionInputs,
                fallbackInput: fallbackInput
            )
            let previewFileName = "preview-with-fallback.jpg"
            let targetIndexFileName = "target-index-with-fallback.png"
            let previewWithFallbackURL = directoryURL.appendingPathComponent(previewFileName)
            let targetIndexWithFallbackURL = directoryURL.appendingPathComponent(targetIndexFileName)
            try jpegData(from: withFallbackResult.image).write(to: previewWithFallbackURL, options: [.atomic])
            try pngData(from: withFallbackResult.targetIndexImage).write(to: targetIndexWithFallbackURL, options: [.atomic])
            fileURLs.append(previewWithFallbackURL)
            fileURLs.append(targetIndexWithFallbackURL)
            previewWithFallbackFileName = previewFileName
            targetIndexWithFallbackFileName = targetIndexFileName
        }

        for contribution in previewResult.targetContributions {
            guard let manifest = targetManifestsByID[contribution.targetID] else {
                continue
            }

            targetManifestsByID[contribution.targetID] = SphericalTargetManifest(
                target: manifest.target,
                status: manifest.status,
                angularErrorDegrees: manifest.angularErrorDegrees,
                coverageContributionPercent: contribution.coverageContributionPercent,
                coveredPixelContributionPercent: contribution.coveredPixelContributionPercent,
                debugColorHex: contribution.debugColor.hexString,
                imageFileName: manifest.imageFileName,
                metadataFileName: manifest.metadataFileName,
                capture: manifest.capture
            )
        }

        let targetManifests = session.targets.compactMap { targetManifestsByID[$0.id] }
        let manifest = SphericalCaptureManifest(
            schemaVersion: 4,
            sessionID: session.id,
            exportedAt: createdAt,
            patternID: session.pattern.id,
            patternName: session.pattern.displayName,
            preview: SphericalPreviewMetadata(
                width: previewResult.width,
                height: previewResult.height,
                fileName: previewURL.lastPathComponent,
                coveragePercent: previewResult.coveragePercent
            ),
            diagnostics: SphericalDiagnosticsMetadata(
                coverageMaskFileName: coverageMaskURL.lastPathComponent,
                targetIndexFileName: targetIndexURL.lastPathComponent,
                fallbackPreviewFileName: fallbackManifests.first?.previewFileName,
                previewWithFallbackFileName: previewWithFallbackFileName,
                targetIndexWithFallbackFileName: targetIndexWithFallbackFileName
            ),
            fallbackSources: fallbackManifests,
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
            previewWidth: previewResult.width,
            previewHeight: previewResult.height,
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

    private func pngData(from image: CGImage) throws -> Data {
        guard let data = UIImage(cgImage: image).pngData() else {
            throw SphericalCaptureExportError.previewEncodingFailed
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
    let sourceID: String
    let capture: HighResolutionFrameCapture
    let debugColor: DebugColor
    let image: CGImage

    init(capturedTarget: SphericalCapturedTarget, image: CGImage) {
        self.sourceID = capturedTarget.target.id
        self.capture = capturedTarget.capture
        self.debugColor = DebugColor.color(for: capturedTarget.target.id)
        self.image = image
    }

    init(fallbackCapture: SphericalFallbackCapture, image: CGImage) {
        self.sourceID = "fallback-ultra-wide"
        self.capture = fallbackCapture.capture
        self.debugColor = .fallback
        self.image = image
    }
}

private struct SphericalPreviewResult {
    let image: CGImage
    let coverageMaskImage: CGImage
    let targetIndexImage: CGImage
    let width: Int
    let height: Int
    let coveragePercent: Double
    let targetContributions: [SphericalTargetContribution]
}

private struct SphericalTargetContribution {
    let targetID: String
    let debugColor: DebugColor
    let coverageContributionPercent: Double
    let coveredPixelContributionPercent: Double
}

private final class SphericalReprojectionPreviewRenderer {
    private let width: Int
    private let height: Int

    init(width: Int = 2048, height: Int = 1024) {
        self.width = width
        self.height = height
    }

    func render(inputs: [ProjectionInput], fallbackInput: ProjectionInput? = nil) throws -> SphericalPreviewResult {
        guard !inputs.isEmpty else {
            throw SphericalCaptureExportError.noCapturedTargets
        }

        let sources = try inputs.map(SourceImage.init(input:))
        let fallbackSource = try fallbackInput.map(SourceImage.init(input:))
        var output = [UInt8](repeating: 0, count: width * height * 4)
        var coverageMask = [UInt8](repeating: 0, count: width * height * 4)
        var targetIndex = [UInt8](repeating: 0, count: width * height * 4)
        var contributionPixelCounts = [String: Int]()
        var coveredPixelCount = 0

        for y in 0..<height {
            for x in 0..<width {
                let direction = worldDirectionForEquirectangularPixel(x: x, y: y)
                let primaryProjection = sample(direction: direction, from: sources)
                let fallbackProjection = primaryProjection == nil
                    ? fallbackSource?.project(worldDirection: direction)
                    : nil
                guard let projection = primaryProjection ?? fallbackProjection else {
                    continue
                }

                let outputIndex = (y * width + x) * 4
                output[outputIndex] = projection.sample.r
                output[outputIndex + 1] = projection.sample.g
                output[outputIndex + 2] = projection.sample.b
                output[outputIndex + 3] = 255

                coverageMask[outputIndex] = 255
                coverageMask[outputIndex + 1] = 255
                coverageMask[outputIndex + 2] = 255
                coverageMask[outputIndex + 3] = 255

                targetIndex[outputIndex] = projection.debugColor.r
                targetIndex[outputIndex + 1] = projection.debugColor.g
                targetIndex[outputIndex + 2] = projection.debugColor.b
                targetIndex[outputIndex + 3] = 255

                contributionPixelCounts[projection.targetID, default: 0] += 1
                coveredPixelCount += 1
            }
        }

        let image = try Self.makeImage(pixels: output, width: width, height: height, shouldInterpolate: true)
        let coverageMaskImage = try Self.makeImage(pixels: coverageMask, width: width, height: height, shouldInterpolate: false)
        let targetIndexImage = try Self.makeImage(pixels: targetIndex, width: width, height: height, shouldInterpolate: false)
        let totalPixelCount = width * height
        let contributions = sources.map { source in
            let pixelCount = contributionPixelCounts[source.targetID] ?? 0
            let coveredContribution = coveredPixelCount > 0
                ? Double(pixelCount) / Double(coveredPixelCount) * 100.0
                : 0
            return SphericalTargetContribution(
                targetID: source.targetID,
                debugColor: source.debugColor,
                coverageContributionPercent: Double(pixelCount) / Double(totalPixelCount) * 100.0,
                coveredPixelContributionPercent: coveredContribution
            )
        }

        let coveragePercent = Double(coveredPixelCount) / Double(totalPixelCount) * 100.0
        return SphericalPreviewResult(
            image: image,
            coverageMaskImage: coverageMaskImage,
            targetIndexImage: targetIndexImage,
            width: width,
            height: height,
            coveragePercent: coveragePercent,
            targetContributions: contributions
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

    private func sample(direction: SIMD3<Float>, from sources: [SourceImage]) -> SourceProjection? {
        var bestSource: SourceProjection?

        for source in sources {
            guard let projection = source.project(worldDirection: direction) else {
                continue
            }
            if bestSource == nil || projection.alignment > bestSource!.alignment {
                bestSource = projection
            }
        }

        return bestSource
    }

    private static func makeImage(pixels: [UInt8], width: Int, height: Int, shouldInterpolate: Bool) throws -> CGImage {
        guard let dataProvider = CGDataProvider(data: Data(pixels) as CFData),
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
                shouldInterpolate: shouldInterpolate,
                intent: .defaultIntent
              )
        else {
            throw SphericalCaptureExportError.previewEncodingFailed
        }
        return image
    }
}

private struct SourceProjection {
    let targetID: String
    let alignment: Float
    let sample: PixelSample
    let debugColor: DebugColor
}

private struct PixelSample {
    let r: UInt8
    let g: UInt8
    let b: UInt8
}

private struct DebugColor {
    let r: UInt8
    let g: UInt8
    let b: UInt8

    var hexString: String {
        String(format: "#%02X%02X%02X", r, g, b)
    }

    static let fallback = DebugColor(r: 0, g: 220, b: 220)

    static func color(for targetID: String) -> DebugColor {
        switch targetID {
        case "horizontal-000":
            return DebugColor(r: 230, g: 57, b: 70)
        case "horizontal-090":
            return DebugColor(r: 29, g: 185, b: 84)
        case "horizontal-180":
            return DebugColor(r: 0, g: 122, b: 255)
        case "horizontal-270":
            return DebugColor(r: 255, g: 149, b: 0)
        case "upward-045":
            return DebugColor(r: 175, g: 82, b: 222)
        case "upward-225":
            return DebugColor(r: 90, g: 200, b: 250)
        case "zenith":
            return DebugColor(r: 255, g: 214, b: 10)
        case "nadir":
            return DebugColor(r: 255, g: 45, b: 85)
        default:
            var hash = UInt32(2166136261)
            for byte in targetID.utf8 {
                hash ^= UInt32(byte)
                hash &*= 16777619
            }
            return DebugColor(
                r: UInt8(64 + (hash & 0x7f)),
                g: UInt8(64 + ((hash >> 8) & 0x7f)),
                b: UInt8(64 + ((hash >> 16) & 0x7f))
            )
        }
    }
}

private final class SourceImage {
    let targetID: String
    let debugColor: DebugColor
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
        let capture = input.capture
        self.targetID = input.sourceID
        self.debugColor = input.debugColor
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
        return SourceProjection(
            targetID: targetID,
            alignment: alignment,
            sample: sample,
            debugColor: debugColor
        )
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
