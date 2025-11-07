import 'package:flutter/material.dart';
import '../models/pose_data.dart';

class PoseOverlay extends CustomPainter {
  final PoseData? currentPose;
  final PoseData? referencePose;
  final double? similarity;

  PoseOverlay({
    this.currentPose,
    this.referencePose,
    this.similarity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 기준 자세 그리기 (초록색, 반투명)
    if (referencePose != null) {
      _drawPose(canvas, size, referencePose!, Colors.green.withAlpha(128));
    }

    // 현재 자세 그리기 (유사도에 따라 색상 변경)
    if (currentPose != null) {
      Color color = Colors.red;
      if (similarity != null) {
        if (similarity! >= 0.85) {
          color = Colors.green;
        } else if (similarity! >= 0.7) {
          color = Colors.yellow;
        }
      }
      _drawPose(canvas, size, currentPose!, color);
    }
  }

  void _drawPose(Canvas canvas, Size size, PoseData pose, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final pointOutlinePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // 관절 그리기
    pose.joints.forEach((name, joint) {
      if (joint.confidence > 0.1) {
        final x = joint.x * size.width;
        final y = (1.0 - joint.y) * size.height; // Y 좌표 반전
        // 큰 점으로 표시 + 흰색 테두리
        canvas.drawCircle(Offset(x, y), 8, pointPaint);
        canvas.drawCircle(Offset(x, y), 8, pointOutlinePaint);
      }
    });

    // 골격 연결선 그리기
    _drawConnection(canvas, size, pose, 'left_shoulder_1', 'right_shoulder_1', paint);
    _drawConnection(canvas, size, pose, 'left_shoulder_1', 'left_elbow_1', paint);
    _drawConnection(canvas, size, pose, 'left_elbow_1', 'left_wrist_1', paint);
    _drawConnection(canvas, size, pose, 'right_shoulder_1', 'right_elbow_1', paint);
    _drawConnection(canvas, size, pose, 'right_elbow_1', 'right_wrist_1', paint);
    _drawConnection(canvas, size, pose, 'left_shoulder_1', 'left_hip_1', paint);
    _drawConnection(canvas, size, pose, 'right_shoulder_1', 'right_hip_1', paint);
    _drawConnection(canvas, size, pose, 'left_hip_1', 'right_hip_1', paint);
    _drawConnection(canvas, size, pose, 'left_hip_1', 'left_knee_1', paint);
    _drawConnection(canvas, size, pose, 'left_knee_1', 'left_ankle_1', paint);
    _drawConnection(canvas, size, pose, 'right_hip_1', 'right_knee_1', paint);
    _drawConnection(canvas, size, pose, 'right_knee_1', 'right_ankle_1', paint);
  }

  void _drawConnection(
    Canvas canvas,
    Size size,
    PoseData pose,
    String startJoint,
    String endJoint,
    Paint paint,
  ) {
    final start = pose.joints[startJoint];
    final end = pose.joints[endJoint];

    if (start != null && end != null && start.confidence > 0.1 && end.confidence > 0.1) {
      final startPoint = Offset(
        start.x * size.width,
        (1.0 - start.y) * size.height,
      );
      final endPoint = Offset(
        end.x * size.width,
        (1.0 - end.y) * size.height,
      );
      canvas.drawLine(startPoint, endPoint, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PoseOverlay oldDelegate) {
    return oldDelegate.currentPose != currentPose ||
        oldDelegate.referencePose != referencePose ||
        oldDelegate.similarity != similarity;
  }
}

