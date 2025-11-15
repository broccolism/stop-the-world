import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

enum AppIconType {
  play,    // 리마인더 중지 상태
  pause,   // 리마인더 실행 중
  dnd,     // 방해금지 모드
}

class AppIconService {
  static const platform = MethodChannel('app_icon_manager');
  
  /// 현재 아이콘 타입 (상태 추적용)
  static AppIconType _currentIconType = AppIconType.play;
  
  /// 현재 아이콘 타입 반환
  static AppIconType get currentIconType => _currentIconType;
  
  /// Play 아이콘으로 변경 (리마인더 중지 상태)
  static Future<void> updateToPlay() async {
    await _updateIcon(AppIconType.play);
  }
  
  /// Pause 아이콘으로 변경 (리마인더 실행 중)
  static Future<void> updateToPause() async {
    await _updateIcon(AppIconType.pause);
  }
  
  /// DND 아이콘으로 변경 (방해금지 모드)
  static Future<void> updateToDnd() async {
    await _updateIcon(AppIconType.dnd);
  }
  
  /// 아이콘 업데이트 (내부 메소드)
  static Future<void> _updateIcon(AppIconType iconType) async {
    if (_currentIconType == iconType) {
      // 이미 같은 아이콘이면 업데이트하지 않음
      debugPrint('[AppIcon] Already showing ${iconType.name} icon');
      return;
    }
    
    try {
      await platform.invokeMethod('updateIcon', {
        'iconType': iconType.name,
      });
      _currentIconType = iconType;
      debugPrint('[AppIcon] Updated to ${iconType.name} icon');
    } on PlatformException catch (e) {
      debugPrint('[AppIcon] Failed to update icon: ${e.message}');
    } catch (e) {
      debugPrint('[AppIcon] Unexpected error: $e');
    }
  }
  
  /// 특정 아이콘 타입으로 직접 변경
  static Future<void> updateIcon(AppIconType iconType) async {
    await _updateIcon(iconType);
  }
}

