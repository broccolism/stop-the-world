import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/pose_service.dart';
import '../models/pose_data.dart';
import '../models/reminder_type.dart';
import '../widgets/camera_preview_widget.dart';

class ReminderPage extends StatefulWidget {
  const ReminderPage({super.key});

  @override
  State<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends State<ReminderPage> {
  final PoseService _poseService = PoseService();
  ReminderType _reminderType = ReminderType.poseMatching;
  
  // 자세 매칭용 변수
  PoseData? _currentPose;
  PoseData? _referencePose;
  double? _similarity;
  String? _snapshotPath;
  double _cameraOpacity = 0.6;
  DateTime? _goodPoseStartTime;
  static const Duration _requiredHoldDuration = Duration(seconds: 3);
  
  // 깜빡임 감지용 변수
  int _currentBlinkCount = 0;
  int _targetBlinkCount = 10;
  
  // 공통 변수
  int? _textureId;
  bool _isInitialized = false;
  String _statusMessage = '카메라 초기화 중...';
  Timer? _detectionTimer;
  bool _hasReference = false;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    debugPrint('[Reminder] Initialize started');
    
    // 리마인더 타입 로드
    _reminderType = await _poseService.loadReminderType();
    debugPrint('[Reminder] Reminder type: $_reminderType');
    
    if (_reminderType == ReminderType.poseMatching) {
      await _initializePoseMatching();
    } else {
      await _initializeBlinkCount();
    }
  }
  
  Future<void> _initializePoseMatching() async {
    try {
      debugPrint('[Reminder] Initializing pose matching mode...');
      
      // 기준 자세 확인
      _hasReference = await _poseService.hasReferencePose();
      debugPrint('[Reminder] Has reference: $_hasReference');
      
      if (!_hasReference) {
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
      debugPrint('[Reminder] Reference pose loaded with ${_referencePose?.joints.length ?? 0} joints');
      
      // 스냅샷 경로 로드
      _snapshotPath = await _poseService.loadSnapshotPath();
      debugPrint('[Reminder] Snapshot path: $_snapshotPath');
      
      // 카메라 시작
      final textureId = await _poseService.startCamera();
      debugPrint('[Reminder] Camera started with textureId: $textureId');
      
      setState(() {
        _textureId = textureId;
        _isInitialized = true;
        _statusMessage = '기준 자세와 맞춰주세요';
      });
      
      _startPoseDetectionLoop();
      debugPrint('[Reminder] Pose matching initialized successfully');
    } catch (e) {
      debugPrint('[Reminder] Error initializing pose matching: $e');
      setState(() {
        _statusMessage = '초기화 실패: $e';
      });
    }
  }
  
  Future<void> _initializeBlinkCount() async {
    try {
      debugPrint('[Reminder] Initializing blink count mode...');
      
      // 목표 깜빡임 횟수 로드
      _targetBlinkCount = await _poseService.loadBlinkTargetCount();
      debugPrint('[Reminder] Target blink count: $_targetBlinkCount');
      
      // 카메라 시작
      final textureId = await _poseService.startCamera();
      debugPrint('[Reminder] Camera started with textureId: $textureId');
      
      // 깜빡임 카운터 리셋
      await _poseService.resetBlinkCount();
      
      setState(() {
        _textureId = textureId;
        _isInitialized = true;
        _currentBlinkCount = 0;
        _statusMessage = '눈을 깜빡이세요!';
      });
      
      _startBlinkDetectionLoop();
      debugPrint('[Reminder] Blink count initialized successfully');
    } catch (e) {
      debugPrint('[Reminder] Error initializing blink count: $e');
      setState(() {
        _statusMessage = '초기화 실패: $e';
      });
    }
  }

  void _startPoseDetectionLoop() {
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (!mounted || _isClosing) return;
      
      try {
        final pose = await _poseService.detectPose();
        if (pose != null && _referencePose != null) {
          // 기준 자세에 관절이 없으면 에러
          if (_referencePose!.joints.isEmpty) {
            debugPrint('[Reminder] ERROR: Reference pose has no joints!');
            if (mounted && !_isClosing) {
              setState(() {
                _statusMessage = '기준 자세 데이터 오류\n설정을 다시 해주세요';
              });
            }
            return;
          }
          
          final similarity = await _poseService.comparePoses(_referencePose!, pose);
          
          if (mounted && !_isClosing) {
            setState(() {
              _currentPose = pose;
              _similarity = similarity;
              
              // 현재 자세에 관절이 없으면
              if (pose.joints.isEmpty) {
                _statusMessage = '자세가 감지되지 않았습니다';
                _goodPoseStartTime = null; // 타이머 리셋
              } else if (similarity >= 0.50) {
                // 좋은 자세 달성!
                if (_goodPoseStartTime == null) {
                  // 처음 달성한 경우 타이머 시작
                  _goodPoseStartTime = DateTime.now();
                  _statusMessage = '좋아요! 3초간 유지하세요... (${(similarity * 100).toStringAsFixed(1)}%)';
                  debugPrint('[Reminder] Good pose started, timer begins');
                } else {
                  // 이미 타이머가 시작된 경우 경과 시간 확인
                  final elapsed = DateTime.now().difference(_goodPoseStartTime!);
                  final remaining = _requiredHoldDuration - elapsed;
                  
                  if (remaining.inMilliseconds <= 0) {
                    // 3초 달성!
                    _statusMessage = '완벽합니다! (${(similarity * 100).toStringAsFixed(1)}%)';
                    debugPrint('[Reminder] Held for 3 seconds, closing');
                    _closeWithDelay();
                  } else {
                    // 아직 3초 미만
                    final remainingSeconds = (remaining.inMilliseconds / 1000).ceil();
                    _statusMessage = '좋아요! $remainingSeconds초 더 유지... (${(similarity * 100).toStringAsFixed(1)}%)';
                  }
                }
              } else {
                // 유사도가 50% 미만으로 떨어짐 - 타이머 리셋
                if (_goodPoseStartTime != null) {
                  debugPrint('[Reminder] Pose lost, timer reset');
                  _goodPoseStartTime = null;
                }
                
                if (similarity >= 0.35) {
                  _statusMessage = '조금만 더! (${(similarity * 100).toStringAsFixed(1)}%)';
                } else {
                  _statusMessage = '자세를 맞춰주세요 (${(similarity * 100).toStringAsFixed(1)}%)';
                }
              }
            });
          }
        } else {
          if (mounted && !_isClosing) {
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

  void _startBlinkDetectionLoop() {
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (!mounted || _isClosing) return;
      
      try {
        final blinkCount = await _poseService.detectBlink();
        
        if (mounted && !_isClosing) {
          setState(() {
            _currentBlinkCount = blinkCount;
            
            if (_currentBlinkCount >= _targetBlinkCount) {
              _statusMessage = '완료! $_currentBlinkCount회 깜빡임';
              debugPrint('[Reminder] Target blink count reached');
              _closeWithDelay();
            } else {
              _statusMessage = '$_currentBlinkCount / $_targetBlinkCount회 깜빡임';
            }
          });
        }
      } catch (e) {
        debugPrint('[Reminder] Blink detection error: $e');
      }
    });
  }

  void _closeWithDelay() {
    if (_isClosing) return;
    
    _isClosing = true;
    _detectionTimer?.cancel();
    _goodPoseStartTime = null; // 타이머 정리
    
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  void _skip() {
    if (_isClosing) return;
    
    _isClosing = true;
    _detectionTimer?.cancel();
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
      body: _reminderType == ReminderType.poseMatching
          ? _buildPoseMatchingUI()
          : _buildBlinkCountUI(),
    );
  }

  Widget _buildPoseMatchingUI() {
    return Stack(
      children: [
          // 1. 기준 자세 이미지 배경 (전체 화면)
          if (_isInitialized && _snapshotPath != null && File(_snapshotPath!).existsSync())
            Positioned.fill(
              child: Image.file(
                File(_snapshotPath!),
                fit: BoxFit.contain,
              ),
            )
          else if (!_isInitialized)
            // 초기화 중 화면
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
          
          // 2. 투명도가 적용된 카메라 프리뷰
          if (_isInitialized)
            CameraPreviewWidget(
              textureId: _textureId,
              currentPose: _currentPose,
              referencePose: _referencePose,
              similarity: _similarity,
              opacity: _cameraOpacity,
            ),
          
          // 3. 투명도 슬라이더 (우측 하단)
          if (_isInitialized)
            Positioned(
              right: 20,
              bottom: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(179),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.opacity,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(height: 8),
                    RotatedBox(
                      quarterTurns: 3, // 세로 슬라이더
                      child: SizedBox(
                        width: 150,
                        child: Slider(
                          value: _cameraOpacity,
                          min: 0.3,
                          max: 1.0,
                          divisions: 7,
                          activeColor: Colors.white,
                          inactiveColor: Colors.white.withAlpha(77),
                          onChanged: (value) {
                            setState(() {
                              _cameraOpacity = value;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(_cameraOpacity * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // 4. 상단 유사도 표시
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
          
          // 5. 상태 메시지
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
          
          // 6. 건너뛰기 버튼 (우측 상단)
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
    );
  }

  Widget _buildBlinkCountUI() {
    return Stack(
      children: [
        // 초기화 중 화면
        if (!_isInitialized)
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
        
        // 카메라 프리뷰 (배경, 투명도 낮게)
        if (_isInitialized && _textureId != null)
          Opacity(
            opacity: 0.3,
            child: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Texture(textureId: _textureId!),
              ),
            ),
          ),
        
        // 중앙 카운터
        if (_isInitialized)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.remove_red_eye,
                  size: 80,
                  color: Colors.white,
                ),
                const SizedBox(height: 32),
                Text(
                  '$_currentBlinkCount',
                  style: const TextStyle(
                    fontSize: 120,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        blurRadius: 20.0,
                        color: Colors.black,
                        offset: Offset(0, 0),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '/ $_targetBlinkCount회',
                  style: const TextStyle(
                    fontSize: 32,
                    color: Colors.white70,
                    shadows: [
                      Shadow(
                        blurRadius: 10.0,
                        color: Colors.black,
                        offset: Offset(0, 0),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(179),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
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
    );
  }

  Color _getSimilarityColor() {
    if (_similarity == null) return Colors.red;
    if (_similarity! >= 0.50) return Colors.green;
    if (_similarity! >= 0.35) return Colors.yellow;
    return Colors.red;
  }
}

