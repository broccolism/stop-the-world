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
      final textureId = await _poseService.startCamera();
      setState(() {
        _textureId = textureId;
        _isInitialized = true;
        _statusMessage = '자세를 취하고 기록 버튼을 누르세요';
      });
      _startDetectionLoop();
    } catch (e) {
      setState(() {
        _statusMessage = '카메라 초기화 실패: $e';
      });
    }
  }

  void _startDetectionLoop() {
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (!mounted) return;
      
      try {
        final pose = await _poseService.detectPose();
        if (mounted) {
          setState(() {
            _currentPose = pose;
          });
        }
      } catch (e) {
        debugPrint('[Settings] Detection error: $e');
      }
    });
  }

  Future<void> _recordPose() async {
    if (_currentPose == null) {
      setState(() {
        _statusMessage = '자세가 감지되지 않았습니다';
      });
      return;
    }

    setState(() {
      _isRecording = true;
      _statusMessage = '자세 저장 중...';
    });

    try {
      await _poseService.saveReferencePose(_currentPose!);
      setState(() {
        _statusMessage = '자세가 저장되었습니다!';
      });

      await Future.delayed(const Duration(seconds: 2));
      
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
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
      body: Column(
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
              children: [
                Column(
                  children: [
                    Text(
                      _statusMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '※ 카메라는 백그라운드에서 작동 중입니다',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      '화면의 색상 점들이 감지된 관절입니다',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.close),
                      label: const Text('취소'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isInitialized && !_isRecording && _currentPose != null
                          ? _recordPose
                          : null,
                      icon: const Icon(Icons.check),
                      label: const Text('자세 기록'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

