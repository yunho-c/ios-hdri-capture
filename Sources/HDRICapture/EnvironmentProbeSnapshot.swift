import Foundation
import Metal

struct EnvironmentProbeSnapshot: Identifiable, Equatable {
    let id: UUID
    let capturedAt: Date
    let textureWidth: Int
    let textureHeight: Int
    let textureDepth: Int
    let textureType: String
    let pixelFormat: String
    let mipmapLevelCount: Int
    let arrayLength: Int
    let storageMode: String
    let usage: String

    init(anchorID: UUID, texture: MTLTexture) {
        id = anchorID
        capturedAt = Date()
        textureWidth = texture.width
        textureHeight = texture.height
        textureDepth = texture.depth
        textureType = texture.textureType.displayName
        pixelFormat = texture.pixelFormat.displayName
        mipmapLevelCount = texture.mipmapLevelCount
        arrayLength = texture.arrayLength
        storageMode = texture.storageMode.displayName
        usage = texture.usage.displayName
    }
}

private extension MTLTextureType {
    var displayName: String {
        switch self {
        case .type1D:
            return "1D"
        case .type1DArray:
            return "1D array"
        case .type2D:
            return "2D"
        case .type2DArray:
            return "2D array"
        case .type2DMultisample:
            return "2D multisample"
        case .typeCube:
            return "Cube"
        case .typeCubeArray:
            return "Cube array"
        case .type3D:
            return "3D"
        case .typeTextureBuffer:
            return "Texture buffer"
        @unknown default:
            return "Unknown (\(rawValue))"
        }
    }
}

private extension MTLPixelFormat {
    var displayName: String {
        switch self {
        case .rgba16Float:
            return "rgba16Float"
        case .rgba32Float:
            return "rgba32Float"
        case .rgba8Unorm:
            return "rgba8Unorm"
        case .rgba8Unorm_srgb:
            return "rgba8Unorm_srgb"
        case .bgra8Unorm:
            return "bgra8Unorm"
        case .bgra8Unorm_srgb:
            return "bgra8Unorm_srgb"
        default:
            return "Pixel format \(rawValue)"
        }
    }
}

private extension MTLStorageMode {
    var displayName: String {
        switch self {
        case .shared:
            return "Shared"
        case .managed:
            return "Managed"
        case .private:
            return "Private"
        case .memoryless:
            return "Memoryless"
        @unknown default:
            return "Unknown (\(rawValue))"
        }
    }
}

private extension MTLTextureUsage {
    var displayName: String {
        var names: [String] = []
        if contains(.shaderRead) {
            names.append("shaderRead")
        }
        if contains(.shaderWrite) {
            names.append("shaderWrite")
        }
        if contains(.renderTarget) {
            names.append("renderTarget")
        }
        if contains(.pixelFormatView) {
            names.append("pixelFormatView")
        }
        if #available(iOS 14.0, *), contains(.shaderAtomic) {
            names.append("shaderAtomic")
        }
        return names.isEmpty ? "Unknown (\(rawValue))" : names.joined(separator: ", ")
    }
}

