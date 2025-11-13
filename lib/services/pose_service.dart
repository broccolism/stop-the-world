import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pose_data.dart';
import '../models/reminder_type.dart';
import '../models/dnd_schedule.dart';

class PoseService {
  static const platform = MethodChannel('pose_detection');

  // 재귀적으로 Map<Object?, Object?>를 Map<String, dynamic>으로 변환
  Map<String, dynamic> _convertMap(dynamic input) {
    if (input == null) return {};
    
    final map = input as Map;
    final result = <String, dynamic>{};
    
    map.forEach((key, value) {
      final stringKey = key.toString();
      if (value is Map) {
        result[stringKey] = _convertMap(value);
      } else {
        result[stringKey] = value;
      }
    });
    
    return result;
  }

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

      final poseMap = _convertMap(result);
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

      final poseMap = _convertMap(result);
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

  Future<String?> captureSnapshot() async {
    try {
      final result = await platform.invokeMethod('captureSnapshot');
      return result as String?;
    } on PlatformException catch (e) {
      throw Exception('Failed to capture snapshot: ${e.message}');
    }
  }

  Future<String?> loadSnapshotPath() async {
    try {
      final result = await platform.invokeMethod('loadSnapshotPath');
      return result as String?;
    } on PlatformException catch (e) {
      throw Exception('Failed to load snapshot path: ${e.message}');
    }
  }

  // MARK: - Blink Detection Methods

  Future<int> detectBlink() async {
    try {
      final result = await platform.invokeMethod('detectBlink');
      return result as int;
    } on PlatformException catch (e) {
      throw Exception('Failed to detect blink: ${e.message}');
    }
  }

  Future<void> resetBlinkCount() async {
    try {
      await platform.invokeMethod('resetBlinkCount');
    } on PlatformException catch (e) {
      throw Exception('Failed to reset blink count: ${e.message}');
    }
  }

  Future<int> getBlinkCount() async {
    try {
      final result = await platform.invokeMethod('getBlinkCount');
      return result as int;
    } on PlatformException catch (e) {
      throw Exception('Failed to get blink count: ${e.message}');
    }
  }

  // MARK: - Reminder Type Management

  Future<void> saveReminderType(ReminderType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reminder_type', type.tostring());
  }

  Future<ReminderType> loadReminderType() async {
    final prefs = await SharedPreferences.getInstance();
    final typeString = prefs.getString('reminder_type') ?? 'poseMatching';
    return ReminderTypeExtension.fromString(typeString);
  }

  Future<void> saveBlinkTargetCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('blink_target_count', count);
  }

  Future<int> loadBlinkTargetCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('blink_target_count') ?? 10;
  }

  Future<void> saveReminderInterval(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reminder_interval_seconds', seconds);
  }

  Future<int> loadReminderInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('reminder_interval_seconds') ?? 300; // 기본값 300초(5분)
  }

  // MARK: - DND Schedule Management

  Future<void> saveDndSchedule(DndSchedule schedule) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(schedule.toJson());
    await prefs.setString('dnd_schedule', jsonString);
  }

  Future<DndSchedule?> loadDndSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('dnd_schedule');
    
    if (jsonString == null) return null;
    
    try {
      final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
      final schedule = DndSchedule.fromJson(jsonMap);
      
      // 오늘 날짜가 아니면 null 반환 (자동으로 만료된 것으로 처리)
      if (!schedule.isToday()) {
        await clearDndSchedule();
        return null;
      }
      
      // 모든 DND 시간이 경과했으면 null 반환 (자동으로 만료된 것으로 처리)
      if (!schedule.hasRemainingTime()) {
        await clearDndSchedule();
        return null;
      }
      
      return schedule;
    } catch (e) {
      // 파싱 오류 시 null 반환
      return null;
    }
  }

  Future<void> clearDndSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dnd_schedule');
  }

  Future<bool> isInDndPeriod() async {
    final schedule = await loadDndSchedule();
    if (schedule == null) return false;
    return schedule.isInDndPeriod();
  }

  Future<bool> hasDndScheduleToday() async {
    final schedule = await loadDndSchedule();
    if (schedule == null || !schedule.isToday() || schedule.timeRanges.isEmpty) {
      return false;
    }
    
    // 모든 DND 시간이 경과했으면 스케줄 삭제하고 false 반환
    if (!schedule.hasRemainingTime()) {
      await clearDndSchedule();
      return false;
    }
    
    return true;
  }

  // MARK: - Blocked Apps Management

  Future<void> saveBlockedApps(List<String> apps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('blocked_apps', apps);
  }

  Future<List<String>> loadBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('blocked_apps') ?? ['zoom.us']; // 기본값: Zoom
  }
}

