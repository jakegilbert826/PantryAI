import SwiftUI
import AVFoundation
import UIKit

/// SwiftUI wrapper around an AVCaptureSession. Calls back with a UIImage when
/// the user taps the shutter or `captureRequest` flips.
struct CameraView: UIViewRepresentable {
    @Binding var captureRequest: UUID?
    var onPhoto: (UIImage) -> Void
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if let id = captureRequest, id != context.coordinator.lastRequest {
            context.coordinator.lastRequest = id
            context.coordinator.capture()
        }
    }

    final class Coordinator: NSObject, AVCapturePhotoCaptureDelegate {
        let parent: CameraView
        let session = AVCaptureSession()
        private let output = AVCapturePhotoOutput()
        private let queue = DispatchQueue(label: "ai.pantry.camera")
        var lastRequest: UUID?

        init(parent: CameraView) {
            self.parent = parent
            super.init()
        }

        func attach(to view: PreviewView) {
            view.session = session
            queue.async { [weak self] in self?.configure() }
        }

        private func configure() {
            session.beginConfiguration()
            session.sessionPreset = .photo
            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input),
                session.canAddOutput(output)
            else {
                DispatchQueue.main.async { self.parent.onError("Couldn't initialise the camera.") }
                session.commitConfiguration()
                return
            }
            session.addInput(input)
            session.addOutput(output)
            session.commitConfiguration()
            session.startRunning()
        }

        func capture() {
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .auto
            output.capturePhoto(with: settings, delegate: self)
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            if let error {
                DispatchQueue.main.async { self.parent.onError(error.localizedDescription) }
                return
            }
            guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
            DispatchQueue.main.async { self.parent.onPhoto(image) }
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var session: AVCaptureSession? {
            get { previewLayer.session }
            set {
                previewLayer.session = newValue
                previewLayer.videoGravity = .resizeAspectFill
            }
        }
    }
}
