import Foundation
import simd

struct SphericalAlignmentSnapshot: Equatable {
    enum State: Equatable {
        case unavailable
        case aligned
        case near
        case turn
        case behind

        var displayName: String {
            switch self {
            case .unavailable:
                return "Unavailable"
            case .aligned:
                return "Aligned"
            case .near:
                return "Near"
            case .turn:
                return "Turn"
            case .behind:
                return "Behind"
            }
        }
    }

    let state: State
    let angularErrorDegrees: Double
    let horizontalHint: String
    let verticalHint: String
    let reticleX: Double
    let reticleY: Double

    static let unavailable = SphericalAlignmentSnapshot(
        state: .unavailable,
        angularErrorDegrees: 0,
        horizontalHint: "Start sphere",
        verticalHint: "",
        reticleX: 0,
        reticleY: 0
    )

    var displayHint: String {
        switch state {
        case .unavailable:
            return horizontalHint
        case .aligned:
            return "hold"
        case .behind:
            return "turn around"
        case .near, .turn:
            if horizontalHint.isEmpty {
                return verticalHint
            }
            if verticalHint.isEmpty {
                return horizontalHint
            }
            return "\(horizontalHint), \(verticalHint)"
        }
    }

    var displayAngularError: String {
        state == .unavailable ? "--" : String(format: "%.1f deg", angularErrorDegrees)
    }

    static func make(cameraTransform: simd_float4x4, target: SphericalTarget?) -> SphericalAlignmentSnapshot {
        guard let target else {
            return .unavailable
        }

        let targetDirection = target.direction
        let cameraForward = simd_normalize(-SIMD3<Float>(
            cameraTransform.columns.2.x,
            cameraTransform.columns.2.y,
            cameraTransform.columns.2.z
        ))
        let cameraRight = simd_normalize(SIMD3<Float>(
            cameraTransform.columns.0.x,
            cameraTransform.columns.0.y,
            cameraTransform.columns.0.z
        ))
        let cameraUp = simd_normalize(SIMD3<Float>(
            cameraTransform.columns.1.x,
            cameraTransform.columns.1.y,
            cameraTransform.columns.1.z
        ))

        let forwardAlignment = simd_dot(cameraForward, targetDirection)
        let angularError = acos(max(-1, min(1, Double(forwardAlignment)))) * 180.0 / .pi
        let cameraRightOffset = simd_dot(cameraRight, targetDirection)
        let cameraUpOffset = simd_dot(cameraUp, targetDirection)
        // The app is portrait-only. ARKit's camera basis is rotated relative to the
        // portrait UI overlay, so map camera-up to screen X and inverted camera-right
        // to screen Y.
        let horizontalOffset = cameraUpOffset
        let verticalOffset = -cameraRightOffset
        let behind = forwardAlignment < -0.2

        let state: State
        if behind {
            state = .behind
        } else if angularError <= 6 {
            state = .aligned
        } else if angularError <= 15 {
            state = .near
        } else {
            state = .turn
        }

        let horizontalHint: String
        if behind {
            horizontalHint = "turn around"
        } else if abs(horizontalOffset) < 0.08 {
            horizontalHint = ""
        } else {
            horizontalHint = horizontalOffset > 0 ? "turn right" : "turn left"
        }

        let verticalHint: String
        if behind || abs(verticalOffset) < 0.08 {
            verticalHint = ""
        } else {
            verticalHint = verticalOffset > 0 ? "tilt up" : "tilt down"
        }

        return SphericalAlignmentSnapshot(
            state: state,
            angularErrorDegrees: angularError,
            horizontalHint: horizontalHint,
            verticalHint: verticalHint,
            reticleX: Double(max(-1, min(1, horizontalOffset * 1.8))),
            reticleY: Double(max(-1, min(1, -verticalOffset * 1.8)))
        )
    }
}
