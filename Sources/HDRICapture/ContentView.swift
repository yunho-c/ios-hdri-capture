import SwiftUI

struct ContentView: View {
    private let rustEncoderVersion = encoderVersion()
    private let rustOutputFormat = targetOutputFormat()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HDRI Capture")
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    Text("Phase 1 architecture scaffold")
                        .foregroundStyle(.secondary)
                }

                Divider()

                LabeledContent("Encoder", value: "Rust \(rustEncoderVersion)")
                LabeledContent("Target output", value: rustOutputFormat)

                Spacer()
            }
            .padding()
            .navigationTitle("HDRICapture")
        }
    }
}
