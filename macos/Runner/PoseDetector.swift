import Cocoa
import Vision

@available(macOS 11.0, *)
class PoseDetector {
    private let visionQueue = DispatchQueue(label: "visionQueue")
    private var frameCount = 0
    
    func detectPose(in pixelBuffer: CVPixelBuffer, completion: @escaping ([String: Any]?) -> Void) {
        visionQueue.async { [weak self] in
            guard let self = self else { return }
            self.frameCount += 1
            
            // 10프레임마다 한 번만 로그
            if self.frameCount % 10 == 0 {
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                NSLog("[PoseDetector] Processing frame #%d: %dx%d", self.frameCount, width, height)
            }
            
            let request = VNDetectHumanBodyPoseRequest()
            request.revision = VNDetectHumanBodyPoseRequestRevision1
            
            // 이미지 방향 설정 (카메라가 거꾸로 될 수 있음)
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .up,
                options: [:]
            )
            
            do {
                try handler.perform([request])
                
                guard let observation = request.results?.first else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                // 관절 데이터 추출
                let poseData = self.extractJoints(from: observation)
                
                DispatchQueue.main.async {
                    completion(poseData)
                }
                
            } catch {
                NSLog("[PoseDetector] Pose detection error: %@", error.localizedDescription)
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    private func extractJoints(from observation: VNHumanBodyPoseObservation) -> [String: Any] {
        var joints: [String: [String: Double]] = [:]
        
        // Vision Framework에서 제공하는 주요 관절들
        let jointNames: [VNHumanBodyPoseObservation.JointName] = [
            .nose,
            .leftEye, .rightEye,
            .leftEar, .rightEar,
            .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow,
            .leftWrist, .rightWrist,
            .leftHip, .rightHip,
            .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle,
            .neck,
            .root
        ]
        
        var detectedCount = 0
        for jointName in jointNames {
            if let joint = try? observation.recognizedPoint(jointName) {
                // 신뢰도 체크 없음 - 모든 감지된 관절 포함
                let keyName = jointName.rawValue.rawValue
                joints[keyName] = [
                    "x": Double(joint.location.x),
                    "y": Double(joint.location.y),
                    "confidence": Double(joint.confidence)
                ]
                detectedCount += 1
                // 각 관절의 이름과 신뢰도 출력
                NSLog("[PoseDetector]   - %@: confidence=%.2f", keyName, joint.confidence)
            }
        }
        
        NSLog("[PoseDetector] Detected %d joints out of %d", detectedCount, jointNames.count)
        NSLog("[PoseDetector] Joint keys: %@", Array(joints.keys).joined(separator: ", "))
        
        // 노트북 사용자는 보통 얼굴과 상체만 보임 - 최소 1개 관절만 있으면 OK
        if detectedCount == 0 {
            NSLog("[PoseDetector] WARNING: No joints detected at all!")
        }
        
        let result: [String: Any] = [
            "joints": joints,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        return result
    }
    
    func comparePoses(_ reference: [String: Any], _ current: [String: Any]) -> Double {
        guard let refJoints = reference["joints"] as? [String: [String: Double]],
              let curJoints = current["joints"] as? [String: [String: Double]] else {
            return 0.0
        }
        
        NSLog("[PoseDetector] Reference joints available: %@", Array(refJoints.keys).joined(separator: ", "))
        NSLog("[PoseDetector] Current joints available: %@", Array(curJoints.keys).joined(separator: ", "))
        
        // 전략: 감지된 모든 관절을 사용해서 비교 (얼굴만 있어도 OK)
        // 양쪽 포즈에서 공통으로 감지된 관절들만 비교
        var totalDistance: Double = 0.0
        var validCount = 0
        
        // 모든 관절에 대해 비교
        for (jointName, refJoint) in refJoints {
            if let curJoint = curJoints[jointName],
               let refX = refJoint["x"],
               let refY = refJoint["y"],
               let curX = curJoint["x"],
               let curY = curJoint["y"] {
                
                let dx = refX - curX
                let dy = refY - curY
                let distance = sqrt(dx * dx + dy * dy)
                
                totalDistance += distance
                validCount += 1
            }
        }
        
        // 최소 1개 관절만 매칭되어도 유사도 계산 (얼굴만 있어도 OK)
        guard validCount > 0 else {
            NSLog("[PoseDetector] No matching joints found for comparison")
            return 0.0
        }
        
        NSLog("[PoseDetector] Comparing %d matching joints", validCount)
        
        // 평균 거리 계산
        let avgDistance = totalDistance / Double(validCount)
        
        // 거리를 유사도로 변환 (매우 관대하게)
        // 0.5를 기준으로 설정 - 얼굴만으로도 쉽게 통과하도록
        let similarity = max(0.0, 1.0 - (avgDistance / 0.5))
        
        NSLog("[PoseDetector] Similarity: %.1f%%, avgDistance: %.4f", similarity * 100, avgDistance)
        
        return similarity
    }
}

