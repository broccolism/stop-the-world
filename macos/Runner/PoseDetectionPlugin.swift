import Cocoa
import FlutterMacOS
import AVFoundation
import Vision

@available(macOS 11.0, *)
public class PoseDetectionPlugin: NSObject, FlutterPlugin {
    private var cameraManager: CameraManager?
    private var poseDetector: PoseDetector?
    private var channel: FlutterMethodChannel?
    private var videoTexture: VideoTexture?
    private var textureRegistry: FlutterTextureRegistry?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "pose_detection",
            binaryMessenger: registrar.messenger
        )
        let instance = PoseDetectionPlugin()
        instance.channel = channel
        instance.textureRegistry = registrar.textures
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startCamera":
            startCamera(result: result)
        case "stopCamera":
            stopCamera(result: result)
        case "detectPose":
            detectPose(result: result)
        case "saveReferencePose":
            if let args = call.arguments as? [String: Any],
               let poseData = args["pose"] as? [String: Any] {
                saveReferencePose(poseData: poseData, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Pose data required",
                                  details: nil))
            }
        case "loadReferencePose":
            loadReferencePose(result: result)
        case "comparePoses":
            if let args = call.arguments as? [String: Any],
               let reference = args["reference"] as? [String: Any],
               let current = args["current"] as? [String: Any] {
                comparePoses(reference: reference, current: current, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Reference and current pose data required",
                                  details: nil))
            }
        case "hasReferencePose":
            hasReferencePose(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func startCamera(result: @escaping FlutterResult) {
        guard let registry = textureRegistry else {
            result(FlutterError(code: "NO_REGISTRY",
                              message: "Texture registry not available",
                              details: nil))
            return
        }
        
        if cameraManager == nil {
            cameraManager = CameraManager()
            poseDetector = PoseDetector()
        }
        
        // VideoTexture 생성
        if videoTexture == nil {
            videoTexture = VideoTexture(registry: registry)
        }
        
        // 프레임 콜백 설정
        cameraManager?.onFrameAvailable = { [weak self] pixelBuffer in
            self?.videoTexture?.onFrameAvailable(pixelBuffer)
        }
        
        cameraManager?.startCamera { [weak self] error in
            if let error = error {
                result(FlutterError(code: "CAMERA_ERROR",
                                  message: error.localizedDescription,
                                  details: nil))
            } else {
                // textureId 반환
                if let textureId = self?.videoTexture?.textureId {
                    result(textureId)
                } else {
                    result(FlutterError(code: "NO_TEXTURE",
                                      message: "Failed to create texture",
                                      details: nil))
                }
            }
        }
    }
    
    private func stopCamera(result: @escaping FlutterResult) {
        cameraManager?.stopCamera()
        videoTexture?.dispose()
        videoTexture = nil
        result(nil)
    }
    
    private func detectPose(result: @escaping FlutterResult) {
        guard let cameraManager = cameraManager,
              let poseDetector = poseDetector else {
            result(FlutterError(code: "NOT_INITIALIZED",
                              message: "Camera not started",
                              details: nil))
            return
        }
        
        cameraManager.captureFrame { [weak self] pixelBuffer in
            guard let pixelBuffer = pixelBuffer else {
                result(nil)
                return
            }
            
            poseDetector.detectPose(in: pixelBuffer) { poseData in
                result(poseData)
            }
        }
    }
    
    private func saveReferencePose(poseData: [String: Any], result: @escaping FlutterResult) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: poseData)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                UserDefaults.standard.set(jsonString, forKey: "reference_pose")
                result(nil)
            } else {
                result(FlutterError(code: "SERIALIZATION_ERROR",
                                  message: "Failed to convert pose data",
                                  details: nil))
            }
        } catch {
            result(FlutterError(code: "SERIALIZATION_ERROR",
                              message: error.localizedDescription,
                              details: nil))
        }
    }
    
    private func loadReferencePose(result: @escaping FlutterResult) {
        if let jsonString = UserDefaults.standard.string(forKey: "reference_pose"),
           let jsonData = jsonString.data(using: .utf8) {
            do {
                let poseData = try JSONSerialization.jsonObject(with: jsonData)
                result(poseData)
            } catch {
                result(FlutterError(code: "DESERIALIZATION_ERROR",
                                  message: error.localizedDescription,
                                  details: nil))
            }
        } else {
            result(nil)
        }
    }
    
    private func comparePoses(reference: [String: Any], current: [String: Any], result: @escaping FlutterResult) {
        guard let poseDetector = poseDetector else {
            result(FlutterError(code: "NOT_INITIALIZED",
                              message: "Pose detector not initialized",
                              details: nil))
            return
        }
        
        let similarity = poseDetector.comparePoses(reference, current)
        result(similarity)
    }
    
    private func hasReferencePose(result: @escaping FlutterResult) {
        let hasReference = UserDefaults.standard.string(forKey: "reference_pose") != nil
        result(hasReference)
    }
}

