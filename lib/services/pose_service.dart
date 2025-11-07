import 'package:flutter/services.dart';
import '../models/pose_data.dart';

class PoseService {
  static const platform = MethodChannel('pose_detection');

  Future<int> startCamera() async {
    try {
      final textureId = await platform.invokeMethod('startCamera');
      return textureId as int;
    } on PlatformException catch (e) {
      throw Exception('Failed to start camera: ${e.message}');
    }
  }

  Future<void> stopCamera() async {
    try {
      await platform.invokeMethod('stopCamera');
    } on PlatformException catch (e) {
      throw Exception('Failed to stop camera: ${e.message}');
    }
  }

  Future<PoseData?> detectPose() async {
    try {
      final result = await platform.invokeMethod('detectPose');
      if (result == null) return null;

      final poseMap = Map<String, dynamic>.from(result as Map);
      return PoseData.fromJson(poseMap);
    } on PlatformException catch (e) {
      throw Exception('Failed to detect pose: ${e.message}');
    }
  }

  Future<void> saveReferencePose(PoseData pose) async {
    try {
      await platform.invokeMethod('saveReferencePose', {
        'pose': pose.toJson(),
      });
    } on PlatformException catch (e) {
      throw Exception('Failed to save reference pose: ${e.message}');
    }
  }

  Future<PoseData?> loadReferencePose() async {
    try {
      final result = await platform.invokeMethod('loadReferencePose');
      if (result == null) return null;

      final poseMap = Map<String, dynamic>.from(result as Map);
      return PoseData.fromJson(poseMap);
    } on PlatformException catch (e) {
      throw Exception('Failed to load reference pose: ${e.message}');
    }
  }

  Future<double> comparePoses(PoseData reference, PoseData current) async {
    try {
      final result = await platform.invokeMethod('comparePoses', {
        'reference': reference.toJson(),
        'current': current.toJson(),
      });
      return (result as num).toDouble();
    } on PlatformException catch (e) {
      throw Exception('Failed to compare poses: ${e.message}');
    }
  }

  Future<bool> hasReferencePose() async {
    try {
      final result = await platform.invokeMethod('hasReferencePose');
      return result as bool;
    } on PlatformException catch (e) {
      throw Exception('Failed to check reference pose: ${e.message}');
    }
  }
}

