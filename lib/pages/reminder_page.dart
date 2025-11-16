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
  DateTime? _noPoseStartTime; // 자세가 감지되지 않은 시작 시간
  bool _showNoPoseBanner = false; // 자세 미감지 배너 표시 여부
  static const Duration _requiredHoldDuration = Duration(seconds: 5);
  static const Duration _noPoseAlertDuration = Duration(seconds: 2);
  static const Duration _noPoseAlertDuration = Duration(seconds: 2);

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
    } else if (_reminderType == ReminderType.blinkCount) {
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
        if (mounted) {
          setState(() {
            _statusMessage = '기준 자세가 설정되지 않았습니다\n2초 후 자동으로 닫힙니다';
          });
        }

        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }

      // 기준 자세 로드
      _referencePose = await _poseService.loadReferencePose();
      debugPrint('[Reminder] Reference pose loaded with ${_referencePose?.joints.length ?? 0} joints');

      // 기준 자세 데이터 검증
      if (_referencePose == null || _referencePose!.joints.isEmpty) {
        debugPrint('[Reminder] ERROR: Invalid reference pose data');
        if (mounted) {
          setState(() {
            _statusMessage = '기준 자세 데이터가 손상되었습니다\n설정에서 다시 기록해주세요';
          });
        }
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }

      // 스냅샷 경로 로드
      _snapshotPath = await _poseService.loadSnapshotPath();
      debugPrint('[Reminder] Snapshot path: $_snapshotPath');

      // 카메라 시작 (에러 핸들링 강화)
      int? textureId;
      try {
        textureId = await _poseService.startCamera();
        debugPrint('[Reminder] Camera started with textureId: $textureId');
      } catch (cameraError) {
        debugPrint('[Reminder] Camera start failed: $cameraError');
        if (mounted) {
          setState(() {
            _statusMessage = '카메라 시작 실패\n카메라 권한을 확인해주세요';
          });
        }
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }

      if (mounted) {
        setState(() {
          _textureId = textureId;
          _isInitialized = true;
          _statusMessage = '기준 자세와 맞춰주세요';
        });
      }

      _startPoseDetectionLoop();
      debugPrint('[Reminder] Pose matching initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('[Reminder] Error initializing pose matching: $e');
      debugPrint('[Reminder] Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _statusMessage = '초기화 실패: $e\n2초 후 닫힙니다';
        });
      }
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _initializeBlinkCount() async {
    try {
      debugPrint('[Reminder] Initializing blink count mode...');

      // 목표 깜빡임 횟수 로드
      _targetBlinkCount = await _poseService.loadBlinkTargetCount();
      debugPrint('[Reminder] Target blink count: $_targetBlinkCount');

      // 카메라 시작 (에러 핸들링 강화)
      int? textureId;
      try {
        textureId = await _poseService.startCamera();
        debugPrint('[Reminder] Camera started with textureId: $textureId');
      } catch (cameraError) {
        debugPrint('[Reminder] Camera start failed: $cameraError');
        if (mounted) {
          setState(() {
            _statusMessage = '카메라 시작 실패\n카메라 권한을 확인해주세요';
          });
        }
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }

      // 깜빡임 카운터 리셋
      try {
        await _poseService.resetBlinkCount();
      } catch (e) {
        debugPrint('[Reminder] Failed to reset blink count: $e');
        // 리셋 실패해도 계속 진행
      }

      if (mounted) {
        setState(() {
          _textureId = textureId;
          _isInitialized = true;
          _currentBlinkCount = 0;
          _statusMessage = '눈을 깜빡이세요!';
        });
      }

      _startBlinkDetectionLoop();
      debugPrint('[Reminder] Blink count initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('[Reminder] Error initializing blink count: $e');
      debugPrint('[Reminder] Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _statusMessage = '초기화 실패: $e\n2초 후 닫힙니다';
        });
      }
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.pop(context);
      }
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

                // 자세 미감지 타이머 시작
                if (_noPoseStartTime == null) {
                  _noPoseStartTime = DateTime.now();
                  _showNoPoseBanner = false;
                } else if (!_showNoPoseBanner) {
                  // 2초 이상 감지되지 않으면 배너 표시
                  final elapsed = DateTime.now().difference(_noPoseStartTime!);
                  if (elapsed >= _noPoseAlertDuration) {
                    _showNoPoseBanner = true;
                  }
                }
              } else {
                // 자세가 감지되면 타이머 리셋
                _noPoseStartTime = null;
                _showNoPoseBanner = false;

                if (similarity >= 0.70) {
                  // 좋은 자세 달성!
                  if (_goodPoseStartTime == null) {
                    // 처음 달성한 경우 타이머 시작
                    _goodPoseStartTime = DateTime.now();
                    _statusMessage = '좋아요! 5초간 유지하세요... (${(similarity * 100).toStringAsFixed(1)}%)';
                    debugPrint('[Reminder] Good pose started at ${DateTime.now()}, timer begins');
                  } else {
                    // 이미 타이머가 시작된 경우 경과 시간 확인
                    final elapsed = DateTime.now().difference(_goodPoseStartTime!);
                    final elapsedSeconds = elapsed.inMilliseconds / 1000.0;
                    final remaining = _requiredHoldDuration - elapsed;

                    debugPrint(
                      '[Reminder] Elapsed: ${elapsedSeconds.toStringAsFixed(1)}s / 5.0s, Similarity: ${(similarity * 100).toStringAsFixed(1)}%',
                    );

                    if (remaining.inMilliseconds <= 0) {
                      // 5초 달성!
                      _statusMessage = '완벽합니다! (${(similarity * 100).toStringAsFixed(1)}%)';
                      debugPrint('[Reminder] ✓ Held for ${elapsedSeconds.toStringAsFixed(1)} seconds, closing now');
                      _closeWithDelay();
                    } else {
                      // 아직 5초 미만
                      final remainingSeconds = (remaining.inMilliseconds / 1000).ceil();
                      _statusMessage = '좋아요! $remainingSeconds초 더 유지... (${(similarity * 100).toStringAsFixed(1)}%)';
                    }
                  }
                } else {
                  // 유사도가 70% 미만으로 떨어짐 - 타이머 리셋
                  if (_goodPoseStartTime != null) {
                    debugPrint('[Reminder] Pose lost, timer reset');
                    _goodPoseStartTime = null;
                  }

                  if (similarity >= 0.55) {
                    _statusMessage = '조금만 더! (${(similarity * 100).toStringAsFixed(1)}%)';
                  } else {
                    _statusMessage = '자세를 맞춰주세요 (${(similarity * 100).toStringAsFixed(1)}%)';
                  }
                }
              }
            });
          }
        } else {
          if (mounted && !_isClosing) {
            setState(() {
              _currentPose = pose;
              _statusMessage = '자세가 감지되지 않았습니다';

              // 자세 미감지 타이머 시작
              if (_noPoseStartTime == null) {
                _noPoseStartTime = DateTime.now();
                _showNoPoseBanner = false;
              } else if (!_showNoPoseBanner) {
                // 2초 이상 감지되지 않으면 배너 표시
                final elapsed = DateTime.now().difference(_noPoseStartTime!);
                if (elapsed >= _noPoseAlertDuration) {
                  _showNoPoseBanner = true;
                }
              }
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

  void _showNoPoseAlert() {
    if (!mounted || _isClosing) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('자세 인식 안내'),
          content: const Text('모니터 각도나 화면과의 거리를 조절해보세요'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    try {
      _poseService.stopCamera();
    } catch (e) {
      debugPrint('[Reminder] Error stopping camera: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyWidget;

    switch (_reminderType) {
      case ReminderType.poseMatching:
        bodyWidget = _buildPoseMatchingUI();
        break;
      case ReminderType.blinkCount:
        bodyWidget = _buildBlinkCountUI();
        break;
    }

    return Scaffold(backgroundColor: Colors.black, body: bodyWidget);
  }

  Widget _buildPoseMatchingUI() {
    return Stack(
      children: [
        // 1. 기준 자세 이미지 배경 (전체 화면)
        if (_isInitialized && _snapshotPath != null && File(_snapshotPath!).existsSync())
          Positioned.fill(child: Image.file(File(_snapshotPath!), fit: BoxFit.contain))
        else if (!_isInitialized)
          // 초기화 중 화면
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Colors.white),
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
              decoration: BoxDecoration(color: Colors.black.withAlpha(179), borderRadius: BorderRadius.circular(20)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.opacity, color: Colors.white, size: 20),
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
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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
                decoration: BoxDecoration(color: _getSimilarityColor().withAlpha(204), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  '${(_similarity! * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
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
                decoration: BoxDecoration(color: Colors.black.withAlpha(179), borderRadius: BorderRadius.circular(15)),
                child: Text(
                  _statusMessage,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

        // 6. 자세 미감지 안내 배너 (상단)
        if (_isInitialized && _showNoPoseBanner)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB84D).withAlpha(230), // 주황색
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(77), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '모니터 각도나 화면과의 거리를 조절해보세요',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () {
                      setState(() {
                        _showNoPoseBanner = false;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),

        // 7. 건너뛰기 버튼 (우측 상단)
        if (_isInitialized)
          Positioned(
            top: 40,
            right: 20,
            child: ElevatedButton(
              onPressed: _skip,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF757575), // 회색
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('건너뛰기', style: TextStyle(fontWeight: FontWeight.w600)),
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
                const CircularProgressIndicator(color: Colors.white),
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
                const Icon(Icons.remove_red_eye, size: 80, color: Colors.white),
                const SizedBox(height: 32),
                Text(
                  '$_currentBlinkCount',
                  style: const TextStyle(
                    fontSize: 120,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 20.0, color: Colors.black, offset: Offset(0, 0))],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '/ $_targetBlinkCount회',
                  style: const TextStyle(
                    fontSize: 32,
                    color: Colors.white70,
                    shadows: [Shadow(blurRadius: 10.0, color: Colors.black, offset: Offset(0, 0))],
                  ),
                ),
                const SizedBox(height: 48),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(color: Colors.black.withAlpha(179), borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
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
                backgroundColor: const Color(0xFF757575), // 회색
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('건너뛰기', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  Color _getSimilarityColor() {
    if (_similarity == null) return const Color(0xFF9E9E9E); // 회색
    if (_similarity! >= 0.70) return const Color(0xFF5B8C85); // 녹색 (세이지 그린)
    if (_similarity! >= 0.55) return const Color(0xFFFFB84D); // 노란색 (경고)
    return const Color(0xFFE57373); // 빨간색 (불일치)
  }
}
