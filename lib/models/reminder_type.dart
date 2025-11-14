enum ReminderType {
  poseMatching,  // 자세 매칭
  blinkCount     // 눈 깜빡임
}

extension ReminderTypeExtension on ReminderType {
  String tostring() {
    switch (this) {
      case ReminderType.poseMatching:
        return 'poseMatching';
      case ReminderType.blinkCount:
        return 'blinkCount';
    }
  }
  
  static ReminderType fromString(String value) {
    switch (value) {
      case 'poseMatching':
        return ReminderType.poseMatching;
      case 'blinkCount':
        return ReminderType.blinkCount;
      default:
        return ReminderType.poseMatching; // 기본값
    }
  }
  
  String get displayName {
    switch (this) {
      case ReminderType.poseMatching:
        return '자세 교정';
      case ReminderType.blinkCount:
        return '눈 깜빡이기';
    }
  }
  
  String get description {
    switch (this) {
      case ReminderType.poseMatching:
        return '올바른 자세를 유지하세요';
      case ReminderType.blinkCount:
        return '눈을 깜빡여서 눈의 피로를 풀어주세요';
    }
  }
}

