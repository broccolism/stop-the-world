import 'dart:async';
import 'package:flutter/material.dart';
import '../services/pose_service.dart';
import '../models/pose_data.dart';
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

  @override
  void initState() {
    super.initState();
    _initializeCamera();
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
    // 테스트용: 자세 감지 여부와 무관하게 무조건 기록 가능
    debugPrint('[Settings] Recording pose - currentPose: ${_currentPose != null ? "${_currentPose!.joints.length} joints" : "NULL"}');

    setState(() {
      _isRecording = true;
      if (_currentPose != null && _currentPose!.joints.isNotEmpty) {
        _statusMessage = '자세 저장 중... (${_currentPose!.joints.length}개 관절)';
      } else {
        _statusMessage = '자세 저장 중... (감지된 관절 없음 - 테스트 모드)';
      }
    });

    try {
      // null이면 빈 PoseData 생성
      final poseToSave = _currentPose ?? PoseData(
        joints: {},
        timestamp: DateTime.now(),
      );
      
      // 자세 데이터 저장
      await _poseService.saveReferencePose(poseToSave);
      
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

      await Future.delayed(const Duration(seconds: 1));
      
      if (mounted) {
        Navigator.pop(context);
      }
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
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        title: const Text('자세 설정'),
      ),
      body: SafeArea(
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
              color: Colors.black87,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _statusMessage,
                    style: const TextStyle(
                      color: Colors.white,
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
                      label: const Text('자세 기록하기'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

