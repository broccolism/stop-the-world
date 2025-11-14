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
    } else {
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      body: SafeArea(
        child: _reminderType == ReminderType.poseMatching
            ? _buildPoseMatchingSettings()
            : _buildBlinkCountSettings(),
      ),
    );
  }

  Widget _buildPoseMatchingSettings() {
    return Column(
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
    );
  }

  Widget _buildBlinkCountSettings() {
    return Center(
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
            const SizedBox(height: 32),
            // 완료 버튼 제거: 사이드바 방식이므로 사용자가 직접 다른 페이지로 이동
          ],
        ),
      ),
    );
  }
}

