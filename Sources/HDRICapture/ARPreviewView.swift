import ARKit
import SwiftUI

struct ARPreviewView: UIViewRepresentable {
    @ObservedObject var viewModel: ARCaptureViewModel

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = viewModel.session
        view.automaticallyUpdatesLighting = true
        view.autoenablesDefaultLighting = false
        view.scene = SCNScene()
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if uiView.session !== viewModel.session {
            uiView.session = viewModel.session
        }
    }
}

