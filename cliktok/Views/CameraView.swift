import SwiftUI
import AVFoundation

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraModel()
    let onRecordingComplete: (URL) -> Void
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all) // Add black background
            
            // Camera preview
            if camera.permissionGranted {
                CameraPreviewView(session: camera.session)
                    .edgesIgnoringSafeArea(.all)
            }
            
            // Error message
            if let error = camera.error {
                Text(error)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
            }
            
            // UI Controls
            if camera.permissionGranted {
                VStack {
                    Spacer()
                    
                    // Recording time
                    if camera.isRecording {
                        Text(formatTime(camera.recordingTime))
                            .foregroundColor(.white)
                            .font(.title)
                            .padding()
                    }
                    
                    // Camera controls
                    HStack(spacing: 60) {
                        // Flip camera button
                        Button(action: {
                            camera.switchCamera()
                        }) {
                            Image(systemName: "camera.rotate")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                        
                        // Record button
                        Button(action: {
                            if camera.isRecording {
                                camera.stopRecording()
                            } else {
                                camera.startRecording()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(camera.isRecording ? .red : .white)
                                    .frame(width: 80, height: 80)
                                
                                if camera.isRecording {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.white)
                                        .frame(width: 30, height: 30)
                                }
                            }
                        }
                        
                        // Cancel button
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .background(Color.black) // Ensure black background
        .onAppear {
            print("CameraView: appeared")
            camera.checkPermissions()
            camera.onRecordingComplete = { url in
                print("CameraView: Recording completed")
                onRecordingComplete(url)
                dismiss()
            }
        }
        .onDisappear {
            print("CameraView: disappeared")
        }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

class CameraModel: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var permissionGranted = false
    @Published var isSessionReady = false
    @Published var error: String?
    
    let session = AVCaptureSession()
    var videoDeviceInput: AVCaptureDeviceInput?
    let movieOutput = AVCaptureMovieFileOutput()
    var timer: Timer?
    var onRecordingComplete: ((URL) -> Void)?
    
    override init() {
        super.init()
        print("CameraModel: Initializing")
        
        // Set up session configuration immediately
        Task { @MainActor in
            await setupSession()
            isSessionReady = true
            print("CameraModel: Session setup complete, isSessionReady = true")
            
            // If permission is already granted, start the session
            if permissionGranted {
                print("CameraModel: Permission already granted, starting session")
                startSession()
            }
        }
    }
    
    func checkPermissions() {
        print("CameraModel: Checking permissions")
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("CameraModel: Permission already authorized")
            permissionGranted = true
            if isSessionReady {
                print("CameraModel: Session ready, starting")
                startSession()
            } else {
                print("CameraModel: Session not ready yet")
            }
        case .notDetermined:
            print("CameraModel: Requesting permission")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    print("CameraModel: Permission granted: \(granted)")
                    self?.permissionGranted = granted
                    if granted && self?.isSessionReady == true {
                        print("CameraModel: Starting session after permission grant")
                        self?.startSession()
                    }
                }
            }
        default:
            print("CameraModel: Permission denied")
            permissionGranted = false
            error = "Camera access denied. Please enable it in Settings."
        }
    }
    
    private func startSession() {
        print("CameraModel: Starting session")
        // Start session in background
        Task { @MainActor in
            if !self.session.isRunning {
                print("CameraModel: Session not running, starting now")
                // Configure and start the session
                session.startRunning()
                print("CameraModel: Session started")
            } else {
                print("CameraModel: Session already running")
            }
        }
    }
    
    private func setupSession() async {
        print("CameraModel: Setting up session")
        session.beginConfiguration()
        
        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: .back) else {
            print("CameraModel: Failed to get video device")
            session.commitConfiguration()
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                videoDeviceInput = videoInput
                print("CameraModel: Added video input")
            }
        } catch {
            print("CameraModel: Error setting up video input: \(error)")
            session.commitConfiguration()
            return
        }
        
        // Add audio input
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            print("CameraModel: Failed to get audio device")
            session.commitConfiguration()
            return
        }
        
        do {
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
                print("CameraModel: Added audio input")
            }
        } catch {
            print("CameraModel: Error setting up audio input: \(error)")
            session.commitConfiguration()
            return
        }
        
        // Add movie output
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            print("CameraModel: Added movie output")
        }
        
        // Set high quality preset
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
            print("CameraModel: Set high quality preset")
        }
        
        session.commitConfiguration()
        print("CameraModel: Session configuration committed")
    }
    
    func switchCamera() {
        guard let currentInput = videoDeviceInput else { return }
        
        // Determine new position
        let currentPosition = currentInput.device.position
        let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        
        // Get new device
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                     for: .video,
                                                     position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
            return
        }
        
        Task.detached {
            await self.session.beginConfiguration()
            self.session.removeInput(currentInput)
            
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoDeviceInput = newInput
            }
            
            await self.session.commitConfiguration()
        }
    }
    
    func startRecording() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        movieOutput.startRecording(to: tempURL, recordingDelegate: self)
        isRecording = true
        recordingTime = 0
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.recordingTime += 1
        }
    }
    
    func stopRecording() {
        movieOutput.stopRecording()
        isRecording = false
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        if session.isRunning {
            session.stopRunning()
        }
    }
}

extension CameraModel: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                   didFinishRecordingTo outputFileURL: URL,
                   from connections: [AVCaptureConnection],
                   error: Error?) {
        if let error = error {
            print("Error recording video: \(error.localizedDescription)")
            return
        }
        
        DispatchQueue.main.async {
            self.onRecordingComplete?(outputFileURL)
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    class VideoPreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }
        
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            videoPreviewLayer.frame = bounds
        }
    }
    
    func makeUIView(context: Context) -> VideoPreviewView {
        print("CameraPreviewView: Making VideoPreviewView")
        let view = VideoPreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        
        print("CameraPreviewView: Created view with frame: \(view.frame)")
        return view
    }
    
    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        print("CameraPreviewView: Updating VideoPreviewView bounds")
        uiView.setNeedsLayout()
    }
} 