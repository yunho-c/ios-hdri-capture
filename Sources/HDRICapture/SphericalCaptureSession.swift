import Foundation
import simd

enum SphericalCaptureSessionState: Equatable {
    case idle
    case active
    case complete

    var displayName: String {
        switch self {
        case .idle:
            return "Not started"
        case .active:
            return "Capturing"
        case .complete:
            return "Complete"
        }
    }
}

enum SphericalExportState: Equatable {
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

struct SphericalTarget: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case horizontal
        case upward
        case zenith
        case nadir

        var displayName: String {
            switch self {
            case .horizontal:
                return "Horizontal"
            case .upward:
                return "Upward"
            case .zenith:
                return "Zenith"
            case .nadir:
                return "Nadir"
            }
        }
    }

    let id: String
    let label: String
    let role: Role
    let yawDegrees: Double
    let pitchDegrees: Double

    var displayName: String {
        "\(label) (\(Int(yawDegrees)) deg yaw, \(Int(pitchDegrees)) deg pitch)"
    }

    var direction: SIMD3<Float> {
        let yaw = Float(yawDegrees * .pi / 180.0)
        let pitch = Float(pitchDegrees * .pi / 180.0)
        let x = cos(pitch) * sin(yaw)
        let y = sin(pitch)
        let z = -cos(pitch) * cos(yaw)
        return simd_normalize(SIMD3<Float>(x, y, z))
    }

    static let fastEight: [SphericalTarget] = [
        SphericalTarget(id: "horizontal-000", label: "Front", role: .horizontal, yawDegrees: 0, pitchDegrees: 0),
        SphericalTarget(id: "horizontal-090", label: "Right", role: .horizontal, yawDegrees: 90, pitchDegrees: 0),
        SphericalTarget(id: "horizontal-180", label: "Back", role: .horizontal, yawDegrees: 180, pitchDegrees: 0),
        SphericalTarget(id: "horizontal-270", label: "Left", role: .horizontal, yawDegrees: 270, pitchDegrees: 0),
        SphericalTarget(id: "upward-045", label: "Up Front", role: .upward, yawDegrees: 45, pitchDegrees: 45),
        SphericalTarget(id: "upward-225", label: "Up Back", role: .upward, yawDegrees: 225, pitchDegrees: 45),
        SphericalTarget(id: "zenith", label: "Ceiling", role: .zenith, yawDegrees: 0, pitchDegrees: 80),
        SphericalTarget(id: "nadir", label: "Floor", role: .nadir, yawDegrees: 0, pitchDegrees: -65)
    ]
}

struct SphericalCapturedTarget: Identifiable {
    let id: String
    let target: SphericalTarget
    let capture: HighResolutionFrameCapture
    let angularErrorDegrees: Double
}

final class SphericalCaptureSession: Identifiable {
    let id = UUID()
    let createdAt = Date()
    let targets: [SphericalTarget]
    private(set) var capturedTargets: [String: SphericalCapturedTarget] = [:]
    var currentTargetIndex = 0

    init(targets: [SphericalTarget] = SphericalTarget.fastEight) {
        self.targets = targets
    }

    var currentTarget: SphericalTarget? {
        guard currentTargetIndex < targets.count else {
            return nil
        }
        return targets[currentTargetIndex]
    }

    var capturedCount: Int {
        capturedTargets.count
    }

    var isComplete: Bool {
        capturedCount == targets.count
    }

    var progressDisplay: String {
        "\(capturedCount)/\(targets.count)"
    }

    func status(for target: SphericalTarget) -> String {
        capturedTargets[target.id] == nil ? "Pending" : "Captured"
    }

    func record(capture: HighResolutionFrameCapture, for target: SphericalTarget) {
        let error = Self.angularErrorDegrees(targetDirection: target.direction, cameraForward: capture.cameraForwardWorld)
        capturedTargets[target.id] = SphericalCapturedTarget(
            id: target.id,
            target: target,
            capture: capture,
            angularErrorDegrees: error
        )
        advanceToNextPendingTarget()
    }

    func recaptureCurrentTarget(with capture: HighResolutionFrameCapture) {
        guard let currentTarget else {
            return
        }
        record(capture: capture, for: currentTarget)
    }

    func advanceToNextPendingTarget() {
        guard !isComplete else {
            currentTargetIndex = targets.count
            return
        }

        let startIndex = min(currentTargetIndex, targets.count - 1)
        if let nextIndex = targets[startIndex...].firstIndex(where: { capturedTargets[$0.id] == nil }) {
            currentTargetIndex = nextIndex
            return
        }
        if let nextIndex = targets[..<startIndex].firstIndex(where: { capturedTargets[$0.id] == nil }) {
            currentTargetIndex = nextIndex
        }
    }

    private static func angularErrorDegrees(targetDirection: SIMD3<Float>, cameraForward: SIMD3<Float>) -> Double {
        let dot = max(-1, min(1, Double(simd_dot(simd_normalize(targetDirection), simd_normalize(cameraForward)))))
        return acos(dot) * 180.0 / .pi
    }
}

extension HighResolutionFrameCapture {
    var cameraForwardWorld: SIMD3<Float> {
        guard cameraTransformColumns.count >= 12 else {
            return SIMD3<Float>(0, 0, -1)
        }
        let zColumn = SIMD3<Float>(
            cameraTransformColumns[8],
            cameraTransformColumns[9],
            cameraTransformColumns[10]
        )
        return simd_normalize(-zColumn)
    }
}
