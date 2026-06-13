import SwiftUI

struct ContentView: View {
    @StateObject private var captureModel = ARCaptureViewModel()
    @State private var shareItems: CaptureShareItems?

    private let rustEncoderVersion = encoderVersion()
    private let rustOutputFormat = targetOutputFormat()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ARPreviewView(viewModel: captureModel)
                    .overlay(alignment: .topLeading) {
                        StatusBadge(text: captureModel.statusMessage)
                            .padding()
                    }
                    .overlay {
                        SphericalAlignmentOverlay(
                            alignment: captureModel.sphericalAlignment,
                            isVisible: captureModel.sphericalCaptureState == .active
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 420)
                    .background(Color.black)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ARKit High-Resolution Capture")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text("Capture single high-resolution frames, then validate spherical pose coverage before adding exposure brackets.")
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        statusSection
                        sphericalCaptureSection
                        highResolutionCaptureSection
                        probeSection
                        backendSection
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("HDRICapture")
            .onAppear {
                captureModel.start()
            }
            .onDisappear {
                captureModel.pause()
            }
            .sheet(item: $shareItems) { shareItems in
                ActivityView(activityItems: shareItems.urls)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session")
                .font(.headline)

            LabeledContent("Supported", value: captureModel.isSupported ? "Yes" : "No")
            LabeledContent("Running", value: captureModel.isRunning ? "Yes" : "No")
            LabeledContent("Tracking", value: captureModel.trackingState)
            LabeledContent("Frame time", value: formattedFrameTimestamp)
        }
    }

    private var sphericalCaptureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Single-Exposure Sphere")
                .font(.headline)

            LabeledContent("State", value: captureModel.sphericalCaptureState.displayName)

            if let session = captureModel.sphericalCaptureSession {
                LabeledContent("Pattern", value: session.pattern.displayName)
                LabeledContent("Progress", value: session.progressDisplay)
                if let target = session.currentTarget {
                    LabeledContent("Current target", value: target.displayName)
                    LabeledContent("Target kind", value: target.role.displayName)
                    LabeledContent("Alignment", value: captureModel.sphericalAlignment.displayHint)
                    LabeledContent("Angular error", value: captureModel.sphericalAlignment.displayAngularError)
                } else {
                    LabeledContent("Current target", value: "Complete")
                }

                Button {
                    captureModel.captureCurrentSphericalTarget()
                } label: {
                    Label(
                        captureModel.isCurrentSphericalTargetCaptured ? "Recapture Current Target" : "Capture Current Target",
                        systemImage: "camera.viewfinder"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!captureModel.canCaptureCurrentSphericalTarget)

                Button(role: .destructive) {
                    captureModel.resetSphericalCaptureSession()
                } label: {
                    Label("Reset Sphere", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)

                targetList(session)
                sphericalExportControls
            } else {
                Picker(
                    "Pattern",
                    selection: Binding(
                        get: { captureModel.selectedSphericalPattern.id },
                        set: { captureModel.selectSphericalCapturePattern(id: $0) }
                    )
                ) {
                    ForEach(captureModel.sphericalCapturePatterns) { pattern in
                        Text(pattern.displayName).tag(pattern.id)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Shots", value: "\(captureModel.selectedSphericalPattern.shotCount)")
                Text(captureModel.selectedSphericalPattern.shortDescription)
                    .foregroundStyle(.secondary)

                Button {
                    captureModel.startSphericalCaptureSession()
                } label: {
                    Label(captureModel.selectedSphericalPattern.startButtonTitle, systemImage: "globe")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!captureModel.isRunning)
            }
        }
    }

    private func targetList(_ session: SphericalCaptureSession) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(session.targets) { target in
                let captured = session.capturedTargets[target.id]
                HStack {
                    Text(target.label)
                        .fontWeight(target.id == session.currentTarget?.id ? .semibold : .regular)
                    Spacer()
                    if let captured {
                        HStack(spacing: 8) {
                            Text(String(format: "%.1f deg", captured.angularErrorDegrees))
                                .foregroundStyle(.secondary)

                            if target.id == session.currentTarget?.id {
                                Text("Current")
                                    .foregroundStyle(.blue)
                            } else {
                                Button {
                                    captureModel.selectSphericalTargetForRecapture(target)
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .accessibilityLabel("Recapture \(target.label)")
                            }
                        }
                    } else if target.id == session.currentTarget?.id {
                        Text("Current")
                            .foregroundStyle(.blue)
                    } else {
                        Text(session.status(for: target))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
        }
    }

    private var sphericalExportControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Sphere export", value: captureModel.sphericalExportState.displayName)

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    captureModel.exportSphericalCaptureSession()
                } label: {
                    Label("Export Sphere Bundle", systemImage: "square.and.arrow.down.on.square")
                }
                .buttonStyle(.bordered)
                .disabled(!captureModel.canExportSphericalSession)

                if let export = captureModel.latestSphericalExport {
                    Button {
                        shareItems = CaptureShareItems(urls: export.shareURLs)
                    } label: {
                        Label("Share Sphere Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let export = captureModel.latestSphericalExport {
                LabeledContent("Bundle", value: export.displayDirectoryName)
                LabeledContent("Preview", value: export.displayPreviewResolution)
                LabeledContent("Preview coverage", value: export.displayCoverage)
                LabeledContent("Files", value: "\(export.shareURLs.count)")
            }
        }
    }

    private var highResolutionCaptureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("High-Resolution Still")
                .font(.headline)

            LabeledContent("State", value: captureModel.highResolutionCaptureState.displayName)

            if let videoFormat = captureModel.highResolutionVideoFormat {
                LabeledContent("AR video format", value: videoFormat.displayName)
                LabeledContent("Camera", value: "\(videoFormat.captureDevicePosition), \(videoFormat.captureDeviceType)")
                LabeledContent("Recommended", value: videoFormat.isRecommendedForHighResolutionFrameCapturing ? "Yes" : "No")
            } else {
                Text("No recommended high-resolution ARKit video format was reported for this device.")
                    .foregroundStyle(.secondary)
            }

            Button {
                captureModel.captureHighResolutionFrame()
            } label: {
                Label("Capture High-Res Frame", systemImage: "camera.aperture")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!captureModel.canCaptureHighResolutionFrame)

            if let capture = captureModel.latestHighResolutionCapture {
                LabeledContent("Captured image", value: capture.displayResolution)
                LabeledContent("Pixel format", value: capture.pixelFormat)
                LabeledContent("Planes", value: "\(capture.planeCount)")
                LabeledContent("Frame time", value: capture.displayTimestamp)
                LabeledContent("Tracking", value: capture.trackingState)
                LabeledContent("Exposure", value: capture.displayExposureDuration)
                LabeledContent("Exposure offset", value: capture.displayExposureOffset)
                LabeledContent("Camera pose", value: capture.displayCameraTranslation)
                LabeledContent("Intrinsics", value: capture.displayIntrinsics)
                exportControls
            } else {
                Text("Capture a frame to inspect still-image resolution, AR pose, intrinsics, and exposure metadata.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var exportControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Export", value: captureModel.captureExportState.displayName)

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    captureModel.exportLatestCaptureDebugBundle()
                } label: {
                    Label("Export Debug Bundle", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(!captureModel.canExportLatestCapture)

                if let export = captureModel.latestExport {
                    Button {
                        shareItems = CaptureShareItems(urls: export.shareURLs)
                    } label: {
                        Label("Share Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let export = captureModel.latestExport {
                LabeledContent("Bundle", value: export.displayDirectoryName)
                LabeledContent("Files", value: export.displayFileNames)
            }
        }
    }

    private var probeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Environment Probe")
                .font(.headline)

            LabeledContent("Probe count", value: "\(captureModel.probeCount)")

            if let probe = captureModel.latestProbe {
                LabeledContent("Texture", value: "\(probe.textureWidth)x\(probe.textureHeight)")
                LabeledContent("Type", value: probe.textureType)
                LabeledContent("Pixel format", value: probe.pixelFormat)
                LabeledContent("Mip levels", value: "\(probe.mipmapLevelCount)")
                LabeledContent("Array length", value: "\(probe.arrayLength)")
                LabeledContent("Storage", value: probe.storageMode)
                LabeledContent("Usage", value: probe.usage)
            } else {
                Text("Waiting for ARKit to publish an environment texture.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var backendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Backend")
                .font(.headline)

            LabeledContent("Encoder", value: "Rust \(rustEncoderVersion)")
            LabeledContent("Target output", value: rustOutputFormat)
        }
    }

    private var formattedFrameTimestamp: String {
        guard let latestFrameTimestamp = captureModel.latestFrameTimestamp else {
            return "Waiting"
        }
        return String(format: "%.2f", latestFrameTimestamp)
    }
}

private struct StatusBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.65), in: Capsule())
    }
}

private struct SphericalAlignmentOverlay: View {
    let alignment: SphericalAlignmentSnapshot
    let isVisible: Bool

    var body: some View {
        GeometryReader { geometry in
            if isVisible {
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let target = CGPoint(
                    x: center.x + alignment.reticleX * geometry.size.width * 0.36,
                    y: center.y + alignment.reticleY * geometry.size.height * 0.36
                )

                ZStack {
                    Reticle(color: .white.opacity(0.75), size: 46, lineWidth: 2)
                        .position(center)

                    Reticle(color: color, size: 58, lineWidth: 4)
                        .position(target)

                    VStack(spacing: 5) {
                        Text(alignment.displayHint)
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text(alignment.displayAngularError)
                            .font(.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.62), in: Capsule())
                    .position(x: center.x, y: max(42, target.y - 70))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var color: Color {
        switch alignment.state {
        case .unavailable:
            return .gray
        case .aligned:
            return .green
        case .near:
            return .yellow
        case .turn:
            return .orange
        case .behind:
            return .red
        }
    }
}

private struct Reticle: View {
    let color: Color
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: lineWidth)
                .frame(width: size, height: size)
            Rectangle()
                .fill(color)
                .frame(width: size * 0.42, height: lineWidth)
            Rectangle()
                .fill(color)
                .frame(width: lineWidth, height: size * 0.42)
        }
        .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
    }
}

private struct CaptureShareItems: Identifiable {
    let id = UUID()
    let urls: [URL]
}
