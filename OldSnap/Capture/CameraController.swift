import AVFoundation
import CoreImage
import UIKit
import Combine

/// AVFoundation capture wrapped for SwiftUI. Video frames run through the
/// film engine's preview path and publish as CGImages; stills capture at full
/// resolution and land in the active roll. Frame policy per the quality floor:
/// if a preview render is still in flight we drop the incoming frame — preview
/// quality degrades before framerate ever does.
final class CameraController: NSObject, ObservableObject {
    @Published var previewFrame: CGImage?
    @Published var isAuthorized = false
    @Published var flashOn = false
    @Published var timerSeconds = 0            // 0 / 3 / 10
    @Published var usingFrontCamera = false
    @Published var countdown: Int?

    var activeStock: FilmStock = FilmStockLibrary.c35
    var onCapture: ((Data) -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "os.camera.session")
    private let renderQueue = DispatchQueue(label: "os.camera.render")
    private let previewContext = CIContext(options: [.cacheIntermediates: false])
    private var renderBusy = false
    private var previewSeed = SeededRandom.freshSeed()

    // MARK: - Lifecycle

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted { self?.configureAndRun() }
                }
            }
        default:
            isAuthorized = false
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSession()
            self.session.startRunning()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        session.inputs.forEach(session.removeInput)

        let position: AVCaptureDevice.Position = usingFrontCamera ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: renderQueue)
            session.addOutput(videoOutput)
        }
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            connection.isVideoMirrored = usingFrontCamera
        }
        session.commitConfiguration()
    }

    func flipCamera() {
        usingFrontCamera.toggle()
        sessionQueue.async { [weak self] in self?.configureSession() }
    }

    // MARK: - Capture

    func triggerShutter() {
        if timerSeconds > 0 {
            runCountdown(from: timerSeconds)
        } else {
            capture()
        }
    }

    private func runCountdown(from seconds: Int) {
        countdown = seconds
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let next = (self.countdown ?? 1) - 1
            if next <= 0 {
                timer.invalidate()
                self.countdown = nil
                self.capture()
            } else {
                self.countdown = next
            }
        }
    }

    private func capture() {
        let settings = AVCapturePhotoSettings()
        if !usingFrontCamera, photoOutput.supportedFlashModes.contains(.on) {
            settings.flashMode = flashOn ? .on : .off
        }
        SoundHaptics.shared.shutter(for: activeStock.id)
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

// MARK: - Live preview frames

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Drop the frame if the previous render hasn't finished — never queue.
        guard !renderBusy, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        renderBusy = true
        defer { renderBusy = false }

        autoreleasepool {
            var image = CIImage(cvPixelBuffer: pixelBuffer)
            // Preview at reduced scale keeps the full pipeline realtime.
            let targetEdge: CGFloat = 1080
            let longEdge = max(image.extent.width, image.extent.height)
            if longEdge > targetEdge {
                image = image.transformed(by: .init(scaleX: targetEdge / longEdge,
                                                    y: targetEdge / longEdge))
            }
            let filtered = FilmEngine.shared.previewImage(for: image, stock: activeStock,
                                                          seed: previewSeed)
            if let cg = previewContext.createCGImage(filtered, from: filtered.extent) {
                DispatchQueue.main.async { [weak self] in self?.previewFrame = cg }
            }
        }
    }
}

// MARK: - Still capture

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onCapture?(data)
        }
    }
}
