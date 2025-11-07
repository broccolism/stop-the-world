import Cocoa
import Vision

@available(macOS 11.0, *)
class PoseDetector {
    private let visionQueue = DispatchQueue(label: "visionQueue")
    
    func detectPose(in pixelBuffer: CVPixelBuffer, completion: @escaping ([String: Any]?) -> Void) {
        visionQueue.async {
            let request = VNDetectHumanBodyPoseRequest()
            request.revision = VNDetectHumanBodyPoseRequestRevision1
            
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            
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
                print("Pose detection error: \(error)")
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
        
        for jointName in jointNames {
            if let joint = try? observation.recognizedPoint(jointName),
               joint.confidence > 0.1 {  // 신뢰도 임계값
                joints[jointName.rawValue.rawValue] = [
                    "x": Double(joint.location.x),
                    "y": Double(joint.location.y),
                    "confidence": Double(joint.confidence)
                ]
            }
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
        
        // 주요 관절만 선택 (어깨, 팔꿈치, 눈, 귀)
        let keyJoints = [
            "left_shoulder_1", "right_shoulder_1",
            "left_elbow_1", "right_elbow_1",
            "left_eye_1", "right_eye_1",
            "left_ear_1", "right_ear_1"
        ]
        
        var totalDistance: Double = 0.0
        var validCount = 0
        
        for jointName in keyJoints {
            if let refJoint = refJoints[jointName],
               let curJoint = curJoints[jointName],
               let refX = refJoint["x"],
               let refY = refJoint["y"],
               let curX = curJoint["x"],
               let curY = curJoint["y"] {
                
                // 유클리드 거리 계산
                let dx = refX - curX
                let dy = refY - curY
                let distance = sqrt(dx * dx + dy * dy)
                
                totalDistance += distance
                validCount += 1
            }
        }
        
        guard validCount > 0 else {
            return 0.0
        }
        
        // 평균 거리 계산
        let avgDistance = totalDistance / Double(validCount)
        
        // 거리를 유사도로 변환
        // 0.2를 기준으로 설정 (정규화된 좌표 기준)
        let similarity = max(0.0, 1.0 - (avgDistance / 0.2))
        
        return similarity
    }
}

