import 'package:flutter/material.dart';
import '../models/pose_data.dart';
import 'pose_overlay.dart';

class CameraPreviewWidget extends StatelessWidget {
  final int? textureId;
  final PoseData? currentPose;
  final PoseData? referencePose;
  final double? similarity;

  const CameraPreviewWidget({
    super.key,
    this.textureId,
    this.currentPose,
    this.referencePose,
    this.similarity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // 카메라 프리뷰 (Texture)
          if (textureId != null)
            Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Texture(textureId: textureId!),
              ),
            )
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.camera_alt,
                    size: 80,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '카메라 초기화 중...',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          // 자세 오버레이 (키포인트 시각화)
          if (currentPose != null)
            CustomPaint(
              painter: PoseOverlay(
                currentPose: currentPose,
                referencePose: referencePose,
                similarity: similarity,
              ),
              size: Size.infinite,
            ),
        ],
      ),
    );
  }
}

