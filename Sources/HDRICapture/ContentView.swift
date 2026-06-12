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
                            Text("ARKit Environment Capture")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text("Phase 2 captures ARKit environment probe texture metadata.")
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        statusSection
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
