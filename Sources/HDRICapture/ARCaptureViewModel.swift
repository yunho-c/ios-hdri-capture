import ARKit
import AVFoundation
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
    @Published private(set) var supportedVideoFormats: [HighResolutionVideoFormatSnapshot] = []
    @Published private(set) var latestHighResolutionCapture: HighResolutionFrameCapture?
    @Published private(set) var captureExportState: CaptureExportState = .idle
    @Published private(set) var latestExport: CaptureExportBundle?
    @Published private(set) var sphericalCaptureState: SphericalCaptureSessionState = .idle
    @Published private(set) var selectedSphericalPattern: SphericalCapturePattern = .defaultPattern
    @Published private(set) var sphericalCaptureSession: SphericalCaptureSession?
    @Published private(set) var sphericalExportState: SphericalExportState = .idle
    @Published private(set) var sphericalFallbackCaptureState: SphericalFallbackCaptureState = .idle
    @Published private(set) var latestSphericalExport: SphericalCaptureExportBundle?
    @Published private(set) var sphericalAlignment: SphericalAlignmentSnapshot = .unavailable

    private var observedProbeIDs = Set<UUID>()
    private var primaryHighResolutionVideoFormat: ARConfiguration.VideoFormat?
    private var ultraWideFallbackVideoFormat: ARConfiguration.VideoFormat?
    private var pendingFallbackVideoFormatSnapshot: HighResolutionVideoFormatSnapshot?
    private let exportWriter = CaptureExportWriter()
    private let sphericalExportWriter = SphericalCaptureExportWriter()

    var canCaptureHighResolutionFrame: Bool {
        isRunning && !highResolutionCaptureState.isCapturing && !highResolutionCaptureState.isUnsupported
    }

    var canExportLatestCapture: Bool {
        latestHighResolutionCapture != nil && !captureExportState.isExporting
    }

    var canCaptureCurrentSphericalTarget: Bool {
        sphericalCaptureState == .active && canCaptureHighResolutionFrame && trackingStateAllowsGuidedCapture
    }

    var canExportSphericalSession: Bool {
        guard let sphericalCaptureSession else {
            return false
        }
        return sphericalCaptureSession.capturedCount > 0 && !sphericalExportState.isExporting
    }

    var canCaptureSphericalFallback: Bool {
        guard let sphericalCaptureSession else {
            return false
        }
        return sphericalCaptureSession.capturedCount > 0
            && ultraWideFallbackVideoFormat != nil
            && canCaptureHighResolutionFrame
            && !sphericalFallbackCaptureState.isCapturing
    }

    var isCurrentSphericalTargetCaptured: Bool {
        guard let sphericalCaptureSession,
              let currentTarget = sphericalCaptureSession.currentTarget
        else {
            return false
        }
        return sphericalCaptureSession.isCaptured(currentTarget)
    }

    var sphericalCapturePatterns: [SphericalCapturePattern] {
        SphericalCapturePattern.all
    }

    var ultraWideFallbackAvailability: String {
        guard let ultraWideFallbackVideoFormat else {
            return "No back ultra-wide ARKit video format found"
        }
        return HighResolutionVideoFormatSnapshot(format: ultraWideFallbackVideoFormat).displayName
    }

    private var trackingStateAllowsGuidedCapture: Bool {
        trackingState == "Normal" || trackingState == "Limited: initializing"
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
        configureWorldTracking(configuration)
        refreshVideoFormats()
        if let recommendedFormat = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing {
            configuration.videoFormat = recommendedFormat
            primaryHighResolutionVideoFormat = recommendedFormat
            highResolutionVideoFormat = HighResolutionVideoFormatSnapshot(format: recommendedFormat)
            highResolutionCaptureState = .idle
        } else {
            primaryHighResolutionVideoFormat = nil
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
        cancelPendingUltraWideFallbackCapture(restorePrimaryFormat: false)
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

    func selectSphericalCapturePattern(id: String) {
        guard sphericalCaptureSession == nil,
              let pattern = sphericalCapturePatterns.first(where: { $0.id == id })
        else {
            return
        }

        selectedSphericalPattern = pattern
    }

    func startSphericalCaptureSession() {
        sphericalCaptureSession = SphericalCaptureSession(pattern: selectedSphericalPattern)
        sphericalCaptureState = .active
        sphericalExportState = .idle
        sphericalFallbackCaptureState = fallbackInitialState()
        latestSphericalExport = nil
        sphericalAlignment = .unavailable
        statusMessage = "Started \(selectedSphericalPattern.displayName) spherical capture"
    }

    func resetSphericalCaptureSession() {
        cancelPendingUltraWideFallbackCapture(restorePrimaryFormat: sphericalFallbackCaptureState.isCapturing)
        sphericalCaptureSession = nil
        sphericalCaptureState = .idle
        sphericalExportState = .idle
        sphericalFallbackCaptureState = fallbackInitialState()
        latestSphericalExport = nil
        sphericalAlignment = .unavailable
        statusMessage = "Reset spherical capture session"
    }

    func captureCurrentSphericalTarget() {
        guard canCaptureCurrentSphericalTarget, var sphericalCaptureSession else {
            return
        }

        guard let target = sphericalCaptureSession.currentTarget else {
            sphericalCaptureState = .complete
            statusMessage = "Spherical capture complete"
            return
        }

        highResolutionCaptureState = .capturing
        statusMessage = "Capturing \(target.label)"

        session.captureHighResolutionFrame { [weak self] frame, error in
            guard let self else {
                return
            }

            if let error {
                self.highResolutionCaptureState = .failed(error.localizedDescription)
                self.statusMessage = "Spherical target capture failed"
                return
            }

            guard let frame else {
                self.highResolutionCaptureState = .failed("ARKit did not return a frame")
                self.statusMessage = "Spherical target capture failed"
                return
            }

            let capture = HighResolutionFrameCapture(
                frame: frame,
                streamingVideoFormat: self.highResolutionVideoFormat
            )
            self.latestHighResolutionCapture = capture
            self.latestExport = nil
            self.captureExportState = .idle
            sphericalCaptureSession.record(capture: capture, for: target)
            self.sphericalCaptureSession = sphericalCaptureSession
            self.latestSphericalExport = nil
            self.sphericalExportState = .idle
            self.highResolutionCaptureState = .succeeded

            if sphericalCaptureSession.isComplete {
                self.sphericalCaptureState = .complete
                self.sphericalAlignment = .unavailable
                self.statusMessage = "Spherical capture complete"
            } else {
                self.sphericalCaptureState = .active
                self.statusMessage = "Captured \(target.label)"
            }
        }
    }

    func recaptureCurrentSphericalTarget() {
        captureCurrentSphericalTarget()
    }

    func selectSphericalTargetForRecapture(_ target: SphericalTarget) {
        guard var sphericalCaptureSession,
              sphericalCaptureSession.selectCapturedTargetForRecapture(targetID: target.id)
        else {
            return
        }

        self.sphericalCaptureSession = sphericalCaptureSession
        sphericalCaptureState = .active
        latestSphericalExport = nil
        sphericalExportState = .idle
        statusMessage = "Ready to recapture \(target.label)"
    }

    func captureUltraWideFallbackLayer() {
        guard canCaptureSphericalFallback,
              let fallbackFormat = ultraWideFallbackVideoFormat
        else {
            return
        }

        sphericalFallbackCaptureState = .capturing
        highResolutionCaptureState = .capturing
        let fallbackSnapshot = HighResolutionVideoFormatSnapshot(format: fallbackFormat)
        highResolutionVideoFormat = fallbackSnapshot
        statusMessage = "Capturing ultra-wide fallback"

        runSession(videoFormat: fallbackFormat, options: [])

        pendingFallbackVideoFormatSnapshot = fallbackSnapshot
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(captureDeferredUltraWideFallbackFrame),
            object: nil
        )
        perform(#selector(captureDeferredUltraWideFallbackFrame), with: nil, afterDelay: 0.45)
    }

    @objc private func captureDeferredUltraWideFallbackFrame() {
        guard let fallbackSnapshot = pendingFallbackVideoFormatSnapshot else {
            return
        }

        pendingFallbackVideoFormatSnapshot = nil
        session.captureHighResolutionFrame { [weak self] frame, error in
            guard let self else {
                return
            }

            self.finishUltraWideFallbackCapture(
                frame: frame,
                error: error,
                fallbackSnapshot: fallbackSnapshot
            )
        }
    }

    private func finishUltraWideFallbackCapture(
        frame: ARFrame?,
        error: Error?,
        fallbackSnapshot: HighResolutionVideoFormatSnapshot
    ) {
        defer {
            restorePrimaryVideoFormat()
        }

        if let error {
            sphericalFallbackCaptureState = .failed(error.localizedDescription)
            highResolutionCaptureState = .failed(error.localizedDescription)
            statusMessage = "Ultra-wide fallback failed"
            return
        }

        guard let frame else {
            sphericalFallbackCaptureState = .failed("ARKit did not return a frame")
            highResolutionCaptureState = .failed("ARKit did not return a frame")
            statusMessage = "Ultra-wide fallback failed"
            return
        }

        guard var sphericalCaptureSession else {
            sphericalFallbackCaptureState = .failed("No active spherical capture session")
            highResolutionCaptureState = .failed("No active spherical capture session")
            statusMessage = "Ultra-wide fallback failed"
            return
        }

        let capture = HighResolutionFrameCapture(
            frame: frame,
            streamingVideoFormat: fallbackSnapshot
        )
        sphericalCaptureSession.recordFallback(capture: capture, videoFormat: fallbackSnapshot)
        self.sphericalCaptureSession = sphericalCaptureSession
        latestSphericalExport = nil
        sphericalExportState = .idle
        sphericalFallbackCaptureState = .captured
        highResolutionCaptureState = .succeeded
        statusMessage = "Ultra-wide fallback captured"
    }

    private func cancelPendingUltraWideFallbackCapture(restorePrimaryFormat: Bool) {
        pendingFallbackVideoFormatSnapshot = nil
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(captureDeferredUltraWideFallbackFrame),
            object: nil
        )
        if restorePrimaryFormat {
            restorePrimaryVideoFormat()
            highResolutionCaptureState = .idle
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

    func exportSphericalCaptureSession() {
        guard let sphericalCaptureSession else {
            sphericalExportState = .failed("Start a spherical capture session before exporting.")
            return
        }

        sphericalExportState = .exporting
        statusMessage = "Exporting spherical capture session"

        do {
            latestSphericalExport = try sphericalExportWriter.writeSessionBundle(for: sphericalCaptureSession)
            sphericalExportState = .exported
            statusMessage = "Spherical capture session exported"
        } catch {
            sphericalExportState = .failed(error.localizedDescription)
            statusMessage = "Spherical export failed"
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

    private func configureWorldTracking(_ configuration: ARWorldTrackingConfiguration) {
        configuration.environmentTexturing = .automatic
        configuration.wantsHDREnvironmentTextures = true
        configuration.isLightEstimationEnabled = true
    }

    private func runSession(videoFormat: ARConfiguration.VideoFormat?, options: ARSession.RunOptions) {
        let configuration = ARWorldTrackingConfiguration()
        configureWorldTracking(configuration)
        if let videoFormat {
            configuration.videoFormat = videoFormat
        }
        session.run(configuration, options: options)
    }

    private func restorePrimaryVideoFormat() {
        runSession(videoFormat: primaryHighResolutionVideoFormat, options: [])
        if let primaryHighResolutionVideoFormat {
            highResolutionVideoFormat = HighResolutionVideoFormatSnapshot(format: primaryHighResolutionVideoFormat)
        }
    }

    private func refreshVideoFormats() {
        let formats = ARWorldTrackingConfiguration.supportedVideoFormats
        supportedVideoFormats = formats.map(HighResolutionVideoFormatSnapshot.init(format:))
        ultraWideFallbackVideoFormat = formats
            .filter { $0.captureDevicePosition == .back && $0.captureDeviceType == .builtInUltraWideCamera }
            .sorted { lhs, rhs in
                if lhs.isRecommendedForHighResolutionFrameCapturing != rhs.isRecommendedForHighResolutionFrameCapturing {
                    return lhs.isRecommendedForHighResolutionFrameCapturing && !rhs.isRecommendedForHighResolutionFrameCapturing
                }
                let lhsArea = lhs.imageResolution.width * lhs.imageResolution.height
                let rhsArea = rhs.imageResolution.width * rhs.imageResolution.height
                if lhsArea != rhsArea {
                    return lhsArea > rhsArea
                }
                return lhs.framesPerSecond > rhs.framesPerSecond
            }
            .first
        sphericalFallbackCaptureState = fallbackInitialState()
    }

    private func fallbackInitialState() -> SphericalFallbackCaptureState {
        ultraWideFallbackVideoFormat == nil
            ? .unavailable("No back ultra-wide ARKit video format found")
            : .idle
    }
}

extension ARCaptureViewModel: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestFrameTimestamp = frame.timestamp
        trackingState = frame.camera.trackingState.displayName
        sphericalAlignment = SphericalAlignmentSnapshot.make(
            cameraTransform: frame.camera.transform,
            target: sphericalCaptureSession?.currentTarget
        )
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
