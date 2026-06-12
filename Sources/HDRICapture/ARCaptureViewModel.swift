import ARKit
import Foundation

final class ARCaptureViewModel: NSObject, ObservableObject {
    let session = ARSession()

    @Published private(set) var isSupported = ARWorldTrackingConfiguration.isSupported
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var trackingState = "Not started"
    @Published private(set) var latestFrameTimestamp: TimeInterval?
    @Published private(set) var probeCount = 0
    @Published private(set) var latestProbe: EnvironmentProbeSnapshot?

    private var observedProbeIDs = Set<UUID>()

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = .main
        if !isSupported {
            statusMessage = "AR world tracking is not supported on this device."
        }
    }

    func start() {
        guard isSupported else {
            statusMessage = "AR world tracking is not supported on this device."
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.environmentTexturing = .automatic
        configuration.wantsHDREnvironmentTextures = true
        configuration.isLightEstimationEnabled = true

        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        observedProbeIDs.removeAll()
        probeCount = 0
        latestProbe = nil
        isRunning = true
        statusMessage = "Scanning for environment probes"
        trackingState = "Starting"
    }

    func pause() {
        session.pause()
        isRunning = false
        statusMessage = "Paused"
    }

    private func recordProbe(_ probe: AREnvironmentProbeAnchor) {
        observedProbeIDs.insert(probe.identifier)
        probeCount = observedProbeIDs.count

        guard let texture = probe.environmentTexture else {
            statusMessage = "Environment probe found; waiting for texture"
            return
        }

        latestProbe = EnvironmentProbeSnapshot(anchorID: probe.identifier, texture: texture)
        statusMessage = "Environment texture available"
    }
}

extension ARCaptureViewModel: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestFrameTimestamp = frame.timestamp
        trackingState = frame.camera.trackingState.displayName
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        anchors.compactMap { $0 as? AREnvironmentProbeAnchor }.forEach(recordProbe)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        anchors.compactMap { $0 as? AREnvironmentProbeAnchor }.forEach(recordProbe)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        isRunning = false
        statusMessage = error.localizedDescription
    }

    func sessionWasInterrupted(_ session: ARSession) {
        statusMessage = "Session interrupted"
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        statusMessage = "Session interruption ended"
    }
}

private extension ARCamera.TrackingState {
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

