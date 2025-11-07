import Cocoa
import AVFoundation

class CameraManager: NSObject {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoQueue = DispatchQueue(label: "videoQueue")
    private var currentPixelBuffer: CVPixelBuffer?
    var onFrameAvailable: ((CVPixelBuffer) -> Void)?
    
    override init() {
        super.init()
    }
    
    func startCamera(completion: @escaping (Error?) -> Void) {
        // 카메라 권한 확인
        checkCameraPermission { [weak self] granted in
            if granted {
                self?.setupCamera(completion: completion)
            } else {
                completion(NSError(domain: "CameraManager",
                                 code: 403,
                                 userInfo: [NSLocalizedDescriptionKey: "Camera permission denied"]))
            }
        }
    }
    
    private func checkCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    private func setupCamera(completion: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let session = AVCaptureSession()
            session.sessionPreset = .hd1280x720 // HD 720p 해상도
            NSLog("[CameraManager] Using HD 1280x720 resolution")
            
            // 카메라 디바이스 찾기
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                            for: .video,
                                                            position: .front) ??
                                    AVCaptureDevice.default(for: .video) else {
                DispatchQueue.main.async {
                    completion(NSError(domain: "CameraManager",
                                     code: 404,
                                     userInfo: [NSLocalizedDescriptionKey: "No camera found"]))
                }
                return
            }
            
            do {
                // 입력 설정
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                }
                
                // 출력 설정
                let output = AVCaptureVideoDataOutput()
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: self.videoQueue)
                
                if session.canAddOutput(output) {
                    session.addOutput(output)
                }
                
                self.captureSession = session
                self.videoOutput = output
                
                // 세션 시작
                DispatchQueue.global(qos: .background).async {
                    session.startRunning()
                }
                
                DispatchQueue.main.async {
                    completion(nil)
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }
    
    func stopCamera() {
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
        currentPixelBuffer = nil
    }
    
    func captureFrame(completion: @escaping (CVPixelBuffer?) -> Void) {
        videoQueue.async { [weak self] in
            completion(self?.currentPixelBuffer)
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // 현재 프레임 저장
        currentPixelBuffer = pixelBuffer
        
        // 프레임 콜백 호출
        onFrameAvailable?(pixelBuffer)
    }
}

