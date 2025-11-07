import 'dart:ui';

class PoseData {
  final Map<String, JointPoint> joints;
  final DateTime timestamp;

  PoseData({
    required this.joints,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    final jointsMap = <String, dynamic>{};
    joints.forEach((key, value) {
      jointsMap[key] = {
        'x': value.x,
        'y': value.y,
        'confidence': value.confidence,
      };
    });

    return {
      'joints': jointsMap,
      'timestamp': timestamp.millisecondsSinceEpoch / 1000.0,
    };
  }

  factory PoseData.fromJson(Map<String, dynamic> json) {
    final jointsMap = json['joints'] as Map<String, dynamic>;
    final joints = <String, JointPoint>{};

    jointsMap.forEach((key, value) {
      final jointData = value as Map<String, dynamic>;
      joints[key] = JointPoint(
        x: (jointData['x'] as num).toDouble(),
        y: (jointData['y'] as num).toDouble(),
        confidence: (jointData['confidence'] as num).toDouble(),
      );
    });

    final timestamp = json['timestamp'] as num;
    
    return PoseData(
      joints: joints,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (timestamp.toDouble() * 1000).toInt(),
      ),
    );
  }
}

class JointPoint {
  final double x;
  final double y;
  final double confidence;

  JointPoint({
    required this.x,
    required this.y,
    required this.confidence,
  });

  Offset toOffset() => Offset(x, y);
}

