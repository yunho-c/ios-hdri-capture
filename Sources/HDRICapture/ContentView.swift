import SwiftUI

struct ContentView: View {
    @StateObject private var captureModel = ARCaptureViewModel()

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
                    .frame(maxWidth: .infinity)
                    .frame(height: 420)
                    .background(Color.black)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ARKit High-Resolution Capture")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text("Phase 3 captures a pose-aligned high-resolution AR frame; environment probes remain a low-resolution lighting reference.")
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        statusSection
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
            } else {
                Text("Capture a frame to inspect still-image resolution, AR pose, intrinsics, and exposure metadata.")
                    .foregroundStyle(.secondary)
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
