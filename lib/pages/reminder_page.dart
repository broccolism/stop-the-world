import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/pose_service.dart';
import '../models/pose_data.dart';
import '../widgets/camera_preview_widget.dart';

class ReminderPage extends StatefulWidget {
  const ReminderPage({super.key});

  @override
  State<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends State<ReminderPage> {
  final PoseService _poseService = PoseService();
  PoseData? _currentPose;
  PoseData? _referencePose;
  double? _similarity;
  int? _textureId;
  bool _isInitialized = false;
  String _statusMessage = '카메라 초기화 중...';
  Timer? _detectionTimer;
  bool _hasReference = false;
  String? _snapshotPath; // 기준 자세 스냅샷 경로

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // 기준 자세 확인
    try {
      _hasReference = await _poseService.hasReferencePose();
      
      if (!_hasReference) {
        // 기준 자세가 없으면 2초 후 자동으로 닫기
        setState(() {
          _statusMessage = '기준 자세가 설정되지 않았습니다\n2초 후 자동으로 닫힙니다';
        });
        
        await Future.delayed(const Duration(seconds: 2));
        
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }

      // 기준 자세 로드
      _referencePose = await _poseService.loadReferencePose();
      
      // 스냅샷 경로 로드
      _snapshotPath = await _poseService.loadSnapshotPath();
      debugPrint('[Reminder] Snapshot path: $_snapshotPath');
      
      // 카메라 시작
      final textureId = await _poseService.startCamera();
      
      setState(() {
        _textureId = textureId;
        _isInitialized = true;
        _statusMessage = '기준 자세와 맞춰주세요';
      });
      
      _startDetectionLoop();
    } catch (e) {
      debugPrint('[Reminder] error while initilizing: $e');
      setState(() {
        _statusMessage = '초기화 실패: $e';
      });
    }
  }

  void _startDetectionLoop() {
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (!mounted) return;
      
      try {
        final pose = await _poseService.detectPose();
        if (pose != null && _referencePose != null) {
          final similarity = await _poseService.comparePoses(_referencePose!, pose);
          
          if (mounted) {
            setState(() {
              _currentPose = pose;
              _similarity = similarity;
              
              // 테스트 모드: 관절이 없으면 자동 통과
              if (pose.joints.isEmpty || _referencePose!.joints.isEmpty) {
                _statusMessage = '테스트 모드: 자동 통과 (관절 감지 없음)';
                Future.delayed(const Duration(seconds: 1), () {
                  if (mounted) {
                    Navigator.pop(context);
                  }
                });
              } else if (similarity >= 0.50) {
                _statusMessage = '완벽합니다! (${(similarity * 100).toStringAsFixed(1)}%)';
                
                // 1초 후 자동으로 닫기
                Future.delayed(const Duration(seconds: 1), () {
                  if (mounted) {
                    Navigator.pop(context);
                  }
                });
              } else if (similarity >= 0.35) {
                _statusMessage = '조금만 더! (${(similarity * 100).toStringAsFixed(1)}%)';
              } else {
                _statusMessage = '자세를 맞춰주세요 (${(similarity * 100).toStringAsFixed(1)}%)';
              }
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _currentPose = pose;
              _statusMessage = '자세가 감지되지 않았습니다';
            });
          }
        }
      } catch (e) {
        debugPrint('[Reminder] Detection error: $e');
      }
    });
  }

  void _skip() {
    Navigator.pop(context);
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
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 카메라 프리뷰 및 자세 오버레이
          if (_isInitialized)
            CameraPreviewWidget(
              textureId: _textureId,
              currentPose: _currentPose,
              referencePose: _referencePose,
              similarity: _similarity,
            )
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          
          // 기준 자세 스냅샷 (좌상단)
          if (_isInitialized && _snapshotPath != null && File(_snapshotPath!).existsSync())
            Positioned(
              top: 20,
              left: 20,
              child: Container(
                width: 150,
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 3),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(128),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: [
                      Image.file(
                        File(_snapshotPath!),
                        fit: BoxFit.cover,
                        width: 150,
                        height: 200,
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          color: Colors.green.withAlpha(179),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: const Text(
                            '기준 자세',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          // 상단 유사도 표시
          if (_isInitialized && _similarity != null)
            Positioned(
              top: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: _getSimilarityColor().withAlpha(204),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${(_similarity! * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          
          // 상태 메시지
          if (_isInitialized)
            Positioned(
              top: 120,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(179),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          
          // 건너뛰기 버튼
          if (_isInitialized)
            Positioned(
              top: 40,
              right: 20,
              child: ElevatedButton(
                onPressed: _skip,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.withAlpha(204),
                  foregroundColor: Colors.white,
                ),
                child: const Text('건너뛰기'),
              ),
            ),
        ],
      ),
    );
  }

  Color _getSimilarityColor() {
    if (_similarity == null) return Colors.red;
    if (_similarity! >= 0.50) return Colors.green;
    if (_similarity! >= 0.35) return Colors.yellow;
    return Colors.red;
  }
}

