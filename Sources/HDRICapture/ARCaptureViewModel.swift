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
    @Published private(set) var highResolutionCaptureState: HighResolutionCaptureState = .idle
    @Published private(set) var highResolutionVideoFormat: HighResolutionVideoFormatSnapshot?
    @Published private(set) var latestHighResolutionCapture: HighResolutionFrameCapture?
    @Published private(set) var captureExportState: CaptureExportState = .idle
    @Published private(set) var latestExport: CaptureExportBundle?

    private var observedProbeIDs = Set<UUID>()
    private let exportWriter = CaptureExportWriter()

    var canCaptureHighResolutionFrame: Bool {
        isRunning && !highResolutionCaptureState.isCapturing && !highResolutionCaptureState.isUnsupported
    }

    var canExportLatestCapture: Bool {
        latestHighResolutionCapture != nil && !captureExportState.isExporting
    }

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
        if let recommendedFormat = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing {
            configuration.videoFormat = recommendedFormat
            highResolutionVideoFormat = HighResolutionVideoFormatSnapshot(format: recommendedFormat)
            highResolutionCaptureState = .idle
        } else {
            highResolutionVideoFormat = nil
            highResolutionCaptureState = .unsupported("No recommended ARKit high-resolution video format")
        }

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

    func captureHighResolutionFrame() {
        guard canCaptureHighResolutionFrame else {
            return
        }

        highResolutionCaptureState = .capturing
        statusMessage = "Capturing high-resolution frame"

        session.captureHighResolutionFrame { [weak self] frame, error in
            guard let self else {
                return
            }

            if let error {
                self.highResolutionCaptureState = .failed(error.localizedDescription)
                self.statusMessage = "High-resolution capture failed"
                return
            }

            guard let frame else {
                self.highResolutionCaptureState = .failed("ARKit did not return a frame")
                self.statusMessage = "High-resolution capture failed"
                return
            }

            self.latestHighResolutionCapture = HighResolutionFrameCapture(
                frame: frame,
                streamingVideoFormat: self.highResolutionVideoFormat
            )
            self.latestExport = nil
            self.captureExportState = .idle
            self.highResolutionCaptureState = .succeeded
            self.statusMessage = "High-resolution frame captured"
        }
    }

    func exportLatestCaptureDebugBundle() {
        guard let latestHighResolutionCapture else {
            captureExportState = .failed(CaptureExportError.missingCapture.localizedDescription)
            return
        }

        captureExportState = .exporting
        statusMessage = "Exporting debug capture bundle"

        do {
            latestExport = try exportWriter.writeDebugBundle(for: latestHighResolutionCapture)
            captureExportState = .exported
            statusMessage = "Debug capture bundle exported"
        } catch {
            captureExportState = .failed(error.localizedDescription)
            statusMessage = "Debug export failed"
        }
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
