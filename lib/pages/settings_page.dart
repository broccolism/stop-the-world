import 'dart:async';
import 'package:flutter/material.dart';
import '../services/pose_service.dart';
import '../models/pose_data.dart';
import '../models/reminder_type.dart';
import '../widgets/camera_preview_widget.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final PoseService _poseService = PoseService();
  PoseData? _currentPose;
  int? _textureId;
  bool _isInitialized = false;
  bool _isRecording = false;
  String _statusMessage = '카메라 초기화 중...';
  Timer? _detectionTimer;
  ReminderType _reminderType = ReminderType.poseMatching;
  int _blinkTargetCount = 10;
  bool _isGuidePanelExpanded = true; // 가이드 패널 펼침/접힘 상태

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final type = await _poseService.loadReminderType();
    final targetCount = await _poseService.loadBlinkTargetCount();
    setState(() {
      _reminderType = type;
      _blinkTargetCount = targetCount;
    });
    
    // 자세 매칭 타입일 때만 카메라 초기화
    if (_reminderType == ReminderType.poseMatching) {
      _initializeCamera();
    } else if (_reminderType == ReminderType.blinkCount) {
      setState(() {
        _isInitialized = true;
        _statusMessage = '눈 깜빡이기 설정';
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      debugPrint('[Settings] Initializing camera...');
      final textureId = await _poseService.startCamera();
      debugPrint('[Settings] Camera initialized with textureId: $textureId');
      setState(() {
        _textureId = textureId;
        _isInitialized = true;
        _statusMessage = '자세를 취하고 기록 버튼을 누르세요';
      });
      _startDetectionLoop();
    } catch (e) {
      debugPrint('[Settings] Camera initialization failed: $e');
      setState(() {
        _statusMessage = '카메라 초기화 실패: $e';
      });
    }
  }

  void _startDetectionLoop() {
    debugPrint('[Settings] Starting detection loop...');
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (!mounted) return;
      
      try {
        final pose = await _poseService.detectPose();
        if (mounted) {
          setState(() {
            _currentPose = pose;
            if (pose != null && pose.joints.isNotEmpty) {
              debugPrint('[Settings] Detected ${pose.joints.length} joints: ${pose.joints.keys.join(", ")}');
              _statusMessage = '${pose.joints.length}개 관절 감지됨 - 자세를 취하고 기록하세요';
            } else {
              _statusMessage = '자세를 감지할 수 없습니다. 상체를 카메라에 보여주세요.';
            }
          });
        }
      } catch (e) {
        debugPrint('[Settings] Detection error: $e');
      }
    });
  }

  Future<void> _recordPose() async {
    debugPrint('[Settings] Recording pose - currentPose: ${_currentPose != null ? "${_currentPose!.joints.length} joints" : "NULL"}');

    // 관절이 감지되지 않았으면 저장하지 않음
    if (_currentPose == null || _currentPose!.joints.isEmpty) {
      setState(() {
        _statusMessage = '자세가 감지되지 않았습니다!\n상체를 카메라에 보여주세요';
      });
      
      // 2초 후 원래 메시지로 복원
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _statusMessage = '자세를 감지할 수 없습니다. 상체를 카메라에 보여주세요.';
          });
        }
      });
      
      return;
    }

    setState(() {
      _isRecording = true;
      _statusMessage = '자세 저장 중... (${_currentPose!.joints.length}개 관절)';
    });

    try {
      // 자세 데이터 저장
      await _poseService.saveReferencePose(_currentPose!);
      debugPrint('[Settings] Saved pose with ${_currentPose!.joints.length} joints');
      
      // 스냅샷 저장
      try {
        final snapshotPath = await _poseService.captureSnapshot();
        debugPrint('[Settings] Snapshot saved to: $snapshotPath');
      } catch (e) {
        debugPrint('[Settings] Failed to save snapshot: $e');
        // 스냅샷 저장 실패해도 자세 데이터는 저장됨
      }
      
      setState(() {
        _statusMessage = '자세가 저장되었습니다! ✓';
      });

      // 사이드바 방식이므로 Navigator.pop() 제거
      // 메시지는 계속 표시됨
    } catch (e) {
      debugPrint('[Settings] Save error: $e');
      setState(() {
        _statusMessage = '저장 실패: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRecording = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _poseService.stopCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget settingsWidget;
    
    switch (_reminderType) {
      case ReminderType.poseMatching:
        settingsWidget = _buildPoseMatchingSettings();
        break;
      case ReminderType.blinkCount:
        settingsWidget = _buildBlinkCountSettings();
        break;
    }
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      body: SafeArea(
        child: settingsWidget,
      ),
    );
  }

  Widget _buildPoseMatchingSettings() {
    return Row(
      children: [
        // 좌측: 카메라 프리뷰 영역 (65% 또는 95%)
        Expanded(
          flex: _isGuidePanelExpanded ? 65 : 95,
          child: Column(
            children: [
              Expanded(
                child: _isInitialized
                    ? CameraPreviewWidget(
                        textureId: _textureId,
                        currentPose: _currentPose,
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(_statusMessage),
                          ],
                        ),
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(
                      color: Color(0xFFE0E0E0),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _statusMessage,
                      style: const TextStyle(
                        color: Color(0xFF757575),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _recordPose,
                        icon: const Icon(Icons.check_circle),
                        label: const Text(
                          '자세 기록하기',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5B8C85),  // 세이지 그린
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // 우측: 자세 가이드 패널 (35% 또는 5%)
        Expanded(
          flex: _isGuidePanelExpanded ? 35 : 5,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                left: BorderSide(
                  color: Color(0xFFE0E0E0),
                  width: 1,
                ),
              ),
            ),
            child: _isGuidePanelExpanded
                ? _buildExpandedGuidePanel()
                : _buildCollapsedGuidePanel(),
          ),
        ),
      ],
    );
  }
  
  // 펼쳐진 가이드 패널
  Widget _buildExpandedGuidePanel() {
    return Column(
      children: [
        // 헤더
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xFFF5F7F6),
            border: Border(
              bottom: BorderSide(
                color: Color(0xFFE0E0E0),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 20,
                color: const Color(0xFF5B8C85),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '올바른 자세 가이드',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF424242),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                iconSize: 20,
                color: const Color(0xFF757575),
                onPressed: () {
                  setState(() {
                    _isGuidePanelExpanded = false;
                  });
                },
                tooltip: '가이드 접기',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        
        // 스크롤 가능한 가이드 내용
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGuideItem(
                  icon: Icons.face,
                  title: '머리와 목',
                  description: '모니터 상단을 눈높이에 맞추세요. 턱을 살짝 당기고 귀가 어깨선상에 오도록 합니다.',
                ),
                const SizedBox(height: 16),
                
                _buildGuideItem(
                  icon: Icons.airline_seat_recline_normal,
                  title: '어깨',
                  description: '어깨의 힘을 빼고 자연스럽게 내립니다. 어깨를 뒤로 살짝 당겨 가슴을 펴주세요.',
                ),
                const SizedBox(height: 16),
                
                _buildGuideItem(
                  icon: Icons.event_seat,
                  title: '등과 허리',
                  description: '등을 곧게 펴고 허리 전체를 의자 등받이에 밀착시킵니다. 허리 쿠션 사용을 권장합니다.',
                ),
                const SizedBox(height: 16),
                
                _buildGuideItem(
                  icon: Icons.accessibility_new,
                  title: '팔꿈치',
                  description: '팔꿈치는 90~110도 사이로 구부리고, 팔이 몸 옆에 편안하게 위치하도록 합니다.',
                ),
                const SizedBox(height: 16),
                
                _buildGuideItem(
                  icon: Icons.back_hand,
                  title: '손과 손목',
                  description: '손목은 일직선을 유지합니다. 키보드를 칠 때 손목이 위아래로 꺾이지 않도록 주의하세요.',
                ),
                const SizedBox(height: 16),
                
                _buildGuideItem(
                  icon: Icons.airline_seat_legroom_normal,
                  title: '무릎과 다리',
                  description: '무릎을 90도로 구부리고, 허벅지가 바닥과 평행이 되도록 합니다.',
                ),
                const SizedBox(height: 16),
                
                _buildGuideItem(
                  icon: Icons.directions_walk,
                  title: '발',
                  description: '발바닥 전체가 바닥에 평평하게 닿도록 합니다. 필요시 발받침대를 사용하세요.',
                ),
                const SizedBox(height: 16),
                
                _buildGuideItem(
                  icon: Icons.tv,
                  title: '모니터 거리',
                  description: '모니터와 눈 사이는 팔 길이(약 50-70cm) 정도가 적당합니다.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  // 접힌 가이드 패널 (세로 탭)
  Widget _buildCollapsedGuidePanel() {
    return InkWell(
      onTap: () {
        setState(() {
          _isGuidePanelExpanded = true;
        });
      },
      child: Container(
        color: const Color(0xFFF5F7F6),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 24,
                color: const Color(0xFF5B8C85),
              ),
              const SizedBox(height: 12),
              RotatedBox(
                quarterTurns: -1,
                child: const Text(
                  '가이드',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF424242),
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Icon(
                Icons.chevron_left,
                size: 20,
                color: const Color(0xFF757575),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildGuideItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF5B8C85).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: const Color(0xFF5B8C85),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF424242),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF757575),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBlinkCountSettings() {
    return Row(
      children: [
        // 좌측: 횟수 설정 영역 (65% 또는 95%)
        Expanded(
          flex: _isGuidePanelExpanded ? 65 : 95,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.remove_red_eye,
                    size: 80,
                    color: Color(0xFF5B8C85),  // 세이지 그린
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '눈 깜빡이기',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF424242),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '눈의 피로를 풀기 위해\n눈을 깜빡이는 연습을 합니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF757575),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFE0E0E0),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          '목표 깜빡임 횟수',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF424242),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: () {
                                if (_blinkTargetCount > 5) {
                                  setState(() {
                                    _blinkTargetCount--;
                                  });
                                  _poseService.saveBlinkTargetCount(_blinkTargetCount);
                                }
                              },
                              icon: const Icon(Icons.remove_circle),
                              color: const Color(0xFF9E9E9E),
                              iconSize: 40,
                            ),
                            const SizedBox(width: 20),
                            Text(
                              '$_blinkTargetCount회',
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF5B8C85),  // 세이지 그린
                              ),
                            ),
                            const SizedBox(width: 20),
                            IconButton(
                              onPressed: () {
                                if (_blinkTargetCount < 30) {
                                  setState(() {
                                    _blinkTargetCount++;
                                  });
                                  _poseService.saveBlinkTargetCount(_blinkTargetCount);
                                }
                              },
                              icon: const Icon(Icons.add_circle),
                              color: const Color(0xFF5B8C85),  // 세이지 그린
                              iconSize: 40,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // 우측: 눈 건강 가이드 패널 (35% 또는 5%)
        Expanded(
          flex: _isGuidePanelExpanded ? 35 : 5,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                left: BorderSide(
                  color: Color(0xFFE0E0E0),
                  width: 1,
                ),
              ),
            ),
            child: _isGuidePanelExpanded
                ? _buildExpandedEyeHealthGuidePanel()
                : _buildCollapsedEyeHealthGuidePanel(),
          ),
        ),
      ],
    );
  }
  
  // 펼쳐진 눈 건강 가이드 패널
  Widget _buildExpandedEyeHealthGuidePanel() {
    return Column(
      children: [
        // 헤더
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xFFF5F7F6),
            border: Border(
              bottom: BorderSide(
                color: Color(0xFFE0E0E0),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.visibility,
                size: 20,
                color: const Color(0xFF5B8C85),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '눈 건강 가이드',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF424242),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                iconSize: 20,
                color: const Color(0xFF757575),
                onPressed: () {
                  setState(() {
                    _isGuidePanelExpanded = false;
                  });
                },
                tooltip: '가이드 접기',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        
        // 스크롤 가능한 가이드 내용
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGuideItem(
                  icon: Icons.timer,
                  title: '20-20-20 규칙',
                  description: '20분마다 20초 동안 20피트(약 6m) 떨어진 곳을 바라보세요. 눈의 긴장을 풀어줍니다.',
                ),
                const SizedBox(height: 16),
                
                _buildGuideItem(
                  icon: Icons.remove_red_eye,
                  title: '자주 깜빡이기',
                  description: '모니터를 볼 때 깜빡임 횟수가 줄어듭니다. 의식적으로 자주 눈을 깜빡여 건조함을 방지하세요.',
                ),
                const SizedBox(height: 16),
                
                _buildGuideItem(
                  icon: Icons.light_mode,
                  title: '적절한 조명',
                  description: '화면과 주변 조명의 밝기를 비슷하게 맞추세요. 너무 밝거나 어두운 환경은 눈에 피로를 줍니다.',
                ),
                const SizedBox(height: 16),
                
                _buildGuideItem(
                  icon: Icons.straighten,
                  title: '화면 거리',
                  description: '모니터는 눈에서 50-70cm 떨어진 곳에 배치하세요. 화면 상단이 눈높이와 같거나 약간 아래에 위치하도록 합니다.',
                ),
                const SizedBox(height: 16),
                
                _buildGuideItem(
                  icon: Icons.rotate_90_degrees_ccw,
                  title: '눈 운동',
                  description: '눈을 좌우, 상하로 천천히 움직이고, 원을 그리듯 돌려주세요. 눈 근육의 긴장을 풀어줍니다.',
                ),
                const SizedBox(height: 16),
                
                _buildGuideItem(
                  icon: Icons.opacity,
                  title: '인공눈물 사용',
                  description: '눈이 건조할 때는 인공눈물을 사용하세요. 특히 장시간 작업 시 도움이 됩니다.',
                ),
                const SizedBox(height: 16),
                
                _buildGuideItem(
                  icon: Icons.brightness_6,
                  title: '화면 밝기 조절',
                  description: '화면 밝기를 주변 환경에 맞게 조절하세요. 블루라이트 필터를 사용하면 더욱 좋습니다.',
                ),
                const SizedBox(height: 16),
                
                _buildGuideItem(
                  icon: Icons.self_improvement,
                  title: '정기적 휴식',
                  description: '1-2시간마다 5-10분씩 완전히 휴식을 취하세요. 자리에서 일어나 스트레칭도 함께 하면 좋습니다.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  // 접힌 눈 건강 가이드 패널 (세로 탭)
  Widget _buildCollapsedEyeHealthGuidePanel() {
    return InkWell(
      onTap: () {
        setState(() {
          _isGuidePanelExpanded = true;
        });
      },
      child: Container(
        color: const Color(0xFFF5F7F6),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.visibility,
                size: 24,
                color: const Color(0xFF5B8C85),
              ),
              const SizedBox(height: 12),
              RotatedBox(
                quarterTurns: -1,
                child: const Text(
                  '가이드',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF424242),
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Icon(
                Icons.chevron_left,
                size: 20,
                color: const Color(0xFF757575),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

