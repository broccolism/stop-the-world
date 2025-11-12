import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/settings_page.dart';
import 'pages/reminder_page.dart';
import 'services/pose_service.dart';
import 'models/reminder_type.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // 메인 앱용 옵션 - 화면 전체 높이 사용 (매우 큰 값을 주면 자동으로 최대 높이로 조절됨)
  WindowOptions windowOptions = const WindowOptions(
    size: Size(500, 10000),
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
    skipTaskbar: false,
    title: 'Posture Reminder',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAlwaysOnTop(false);
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Posture Reminder',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Posture Reminder'),
      routes: {
        '/settings': (context) => const SettingsPage(),
        '/reminder': (context) => const ReminderPage(),
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Timer? _reminderTimer;
  bool _isReminderShowing = false;
  bool _isReminderRunning = false; // 리마인더 실행 중 여부
  final PoseService _poseService = PoseService();
  ReminderType _reminderType = ReminderType.poseMatching; // 현재 선택된 리마인더 타입
  int _reminderInterval = 300; // 리마인더 간격 (초, 기본값 5분)

  // TODO: 나중에 UI에서 편집 가능하게 변경 예정
  final List<String> _blockedApps = ['zoom.us']; // Zoom 앱

  @override
  void initState() {
    super.initState();
    _loadSettings();
    // 자동 시작 제거 - 사용자가 수동으로 시작해야 함
  }
  
  Future<void> _loadSettings() async {
    final type = await _poseService.loadReminderType();
    var interval = await _poseService.loadReminderInterval();
    
    // 최소값 보장 (5분 = 300초)
    if (interval < 300) {
      interval = 300;
      await _poseService.saveReminderInterval(interval);
    }
    
    setState(() {
      _reminderType = type;
      _reminderInterval = interval;
    });
  }

  // 리마인더 시작
  Future<void> _startReminder() async {
    // 자세 매칭 타입일 경우에만 기준 자세 확인
    if (_reminderType == ReminderType.poseMatching) {
      final hasReferencePose = await _hasReferencePose();
      
      if (!hasReferencePose) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('먼저 자세를 설정해주세요!'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
    }
    
    if (_reminderTimer != null) {
      debugPrint('[Reminder] Timer already running');
      return;
    }
    
    setState(() {
      _isReminderRunning = true;
    });
    
    debugPrint('[Reminder] Starting reminder loop');
    _startReminderLoop();
  }
  
  // 리마인더 일시중단
  void _pauseReminder() {
    _reminderTimer?.cancel();
    _reminderTimer = null;
    
    setState(() {
      _isReminderRunning = false;
    });
    
    debugPrint('[Reminder] Paused reminder loop');
  }

  // 기준 자세가 설정되어 있는지 확인
  Future<bool> _hasReferencePose() async {
    try {
      return await _poseService.hasReferencePose();
    } catch (e) {
      debugPrint('[Reminder] Error checking reference pose: $e');
      return false;
    }
  }

  // 블랙리스트 앱이 실행 중인지 확인
  // 참고: Sandbox 모드에서는 프로세스 목록을 읽을 수 없으므로 이 기능은 비활성화됨
  Future<bool> _isBlockedAppRunning() async {
    // Sandbox 모드에서는 ps 명령어 실행 불가
    // 추후 NSWorkspace API를 사용하여 구현 가능
    return false;
  }

  // 리마인더 루프 시작 - 리마인더가 닫힌 후부터 다시 타이머 시작
  void _startReminderLoop() {
    _scheduleNextReminder();
  }
  
  // 다음 리마인더 예약
  void _scheduleNextReminder() {
    if (!_isReminderRunning) {
      debugPrint('[Reminder] Loop stopped, not scheduling next reminder');
      return;
    }

    debugPrint('[Reminder] Scheduling next reminder in $_reminderInterval seconds...');
    _reminderTimer = Timer(Duration(seconds: _reminderInterval), () async {
      if (!_isReminderRunning || _isReminderShowing) {
        debugPrint('[Reminder] Skipping reminder (running: $_isReminderRunning, showing: $_isReminderShowing)');
        _scheduleNextReminder(); // 다시 예약
        return;
      }
      
      // 블랙리스트 앱 체크
      if (await _isBlockedAppRunning()) {
        debugPrint('[Reminder] Blocked app is running, skipping reminder...');
        _scheduleNextReminder(); // 다시 예약
        return;
      }
      
      debugPrint('[Reminder] Showing reminder...');
      await _showReminder();
      
      // 리마인더가 닫힌 후 다음 리마인더 예약
      debugPrint('[Reminder] Reminder closed, scheduling next one');
      _scheduleNextReminder();
    });
  }

  // 설정 페이지 표시
  Future<void> _showSettings() async {
    if (!mounted) return;
    
    try {
      debugPrint('[Settings] Showing settings page');
      
      // 창 크기 변경 (설정 화면용)
      try {
        await windowManager.setSize(const Size(600, 800));
        await Future.delayed(const Duration(milliseconds: 100));
        await windowManager.center();
      } catch (e) {
        debugPrint('[Settings] Window resize error: $e');
      }
      
      // 설정 페이지로 이동
      if (mounted) {
        await Navigator.pushNamed(context, '/settings');
      }
      
      debugPrint('[Settings] Settings page closed');
      
      // 원래 창 크기로 복원
      try {
        await windowManager.setSize(const Size(500, 480));
        await Future.delayed(const Duration(milliseconds: 100));
        await windowManager.center();
      } catch (e) {
        debugPrint('[Settings] Window restore error: $e');
      }
      
      // 자세 설정 완료 후에도 자동 시작하지 않음 (사용자가 수동으로 시작)
      
    } catch (e, stackTrace) {
      debugPrint('[Settings] Error: $e');
      debugPrint('[Settings] Stack trace: $stackTrace');
    }
  }

  // 리마인더 페이지 표시
  Future<void> _showReminder() async {
    if (!mounted) return;
    
    // 기준 자세가 있는지 먼저 확인
    final hasReferencePose = await _hasReferencePose();
    if (!hasReferencePose) {
      debugPrint('[Reminder] No reference pose, skipping reminder');
      return;
    }
    
    _isReminderShowing = true;
    
    try {
      debugPrint('[Reminder] Starting window manager operations...');
      
      // 창 크기 변경 (리마인더 화면용)
      try {
        await windowManager.setSize(const Size(600, 800));
        await Future.delayed(const Duration(milliseconds: 100));
        await windowManager.center();
      } catch (e) {
        debugPrint('[Reminder] Window resize error: $e');
      }
      
      // 최소화되어 있으면 복원
      try {
        await windowManager.restore();
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        debugPrint('[Reminder] Window restore error: $e');
      }
      
      // 최상단으로 올리고 포커스 주기
      try {
        await windowManager.setAlwaysOnTop(true);
        await windowManager.show();
        await windowManager.focus();
      } catch (e) {
        debugPrint('[Reminder] Window focus error: $e');
      }
      
      debugPrint('[Reminder] About to show reminder page...');
      
      // 리마인더 페이지로 이동
      if (mounted) {
        debugPrint('[Reminder] Calling Navigator.pushNamed...');
        await Navigator.pushNamed(context, '/reminder');
        debugPrint('[Reminder] Navigator.pushNamed completed');
      } else {
        debugPrint('[Reminder] Widget not mounted, skipping');
      }
      
      debugPrint('[Reminder] Reminder page closed');
      
      // 원래 창 크기로 복원
      try {
        await windowManager.setSize(const Size(500, 480));
        await Future.delayed(const Duration(milliseconds: 100));
        await windowManager.center();
      } catch (e) {
        debugPrint('[Reminder] Window restore size error: $e');
      }
      
      // 최상단 해제 후 최소화
      try {
        await windowManager.setAlwaysOnTop(false);
        await windowManager.minimize();
      } catch (e) {
        debugPrint('[Reminder] Window minimize error: $e');
      }
      
      debugPrint('[Reminder] Window minimized');
    } catch (e, stackTrace) {
      debugPrint('[Reminder] Error: $e');
      debugPrint('[Reminder] Stack trace: $stackTrace');
    } finally {
      _isReminderShowing = false;
    }
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '설정',
            onPressed: _showSettings,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: '종료',
            onPressed: () async {
              debugPrint('[App] Exiting...');
              _reminderTimer?.cancel();
              await windowManager.destroy();
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const SizedBox(height: 20),
              const Icon(
                Icons.accessibility_new,
                size: 60,
                color: Colors.deepPurple,
              ),
              const SizedBox(height: 16),
              const Text(
                'Posture Reminder',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _reminderType.description,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              // 리마인더 타입 선택
              Opacity(
                opacity: _isReminderRunning ? 0.5 : 1.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButton<ReminderType>(
                    value: _reminderType,
                    underline: Container(),
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: _isReminderRunning ? Colors.grey : Colors.deepPurple,
                    ),
                    dropdownColor: Colors.white,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _isReminderRunning ? Colors.grey : Colors.deepPurple,
                    ),
                    disabledHint: Row(
                      children: [
                        Icon(
                          _reminderType == ReminderType.poseMatching
                              ? Icons.accessibility_new
                              : Icons.remove_red_eye,
                          color: Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _reminderType.displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    items: ReminderType.values.map((ReminderType type) {
                      return DropdownMenuItem<ReminderType>(
                        value: type,
                        child: Row(
                          children: [
                            Icon(
                              type == ReminderType.poseMatching
                                  ? Icons.accessibility_new
                                  : Icons.remove_red_eye,
                              color: Colors.deepPurple,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(type.displayName),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: _isReminderRunning ? null : (ReminderType? newValue) async {
                      if (newValue != null) {
                        setState(() {
                          _reminderType = newValue;
                        });
                        await _poseService.saveReminderType(newValue);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // 리마인더 간격 설정
              Opacity(
                opacity: _isReminderRunning ? 0.5 : 1.0,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.timer, color: Colors.grey, size: 20),
                              SizedBox(width: 8),
                              Text(
                                '리마인더 간격',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${(_reminderInterval / 60).round()}분',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _isReminderRunning ? Colors.grey : Colors.deepPurple,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: _isReminderRunning ? Colors.grey : Colors.deepPurple,
                          inactiveTrackColor: _isReminderRunning 
                              ? Colors.grey.withOpacity(0.3) 
                              : Colors.deepPurple.withOpacity(0.3),
                          thumbColor: _isReminderRunning ? Colors.grey : Colors.deepPurple,
                          overlayColor: _isReminderRunning 
                              ? Colors.grey.withOpacity(0.2) 
                              : Colors.deepPurple.withOpacity(0.2),
                          valueIndicatorColor: _isReminderRunning ? Colors.grey : Colors.deepPurple,
                          valueIndicatorTextStyle: const TextStyle(color: Colors.white),
                          disabledActiveTrackColor: Colors.grey,
                          disabledInactiveTrackColor: Colors.grey.withOpacity(0.3),
                          disabledThumbColor: Colors.grey,
                        ),
                        child: Slider(
                          value: (_reminderInterval / 60).roundToDouble(),
                          min: 5,
                          max: 60,
                          divisions: 11, // 5분 단위로 조절 (5, 10, 15, ..., 60)
                          label: '${(_reminderInterval / 60).round()}분',
                          onChanged: _isReminderRunning ? null : (double value) {
                            setState(() {
                              _reminderInterval = (value * 60).toInt(); // 분을 초로 변환
                            });
                          },
                          onChangeEnd: _isReminderRunning ? null : (double value) async {
                            final intervalSeconds = (value * 60).toInt(); // 분을 초로 변환하여 저장
                            await _poseService.saveReminderInterval(intervalSeconds);
                          },
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '5분',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            '1시간',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // 자세 설정 버튼 (자세 매칭 타입일 경우에만 표시)
              if (_reminderType == ReminderType.poseMatching)
                ElevatedButton.icon(
                  onPressed: _showSettings,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('자세 설정'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
              if (_reminderType == ReminderType.poseMatching) const SizedBox(height: 16),
              // 리마인더 시작/일시중단 버튼
              ElevatedButton.icon(
                onPressed: _isReminderRunning ? _pauseReminder : _startReminder,
                icon: Icon(_isReminderRunning ? Icons.pause_circle : Icons.play_circle),
                label: Text(_isReminderRunning ? '리마인더 일시중단' : '리마인더 시작'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isReminderRunning ? Colors.orange : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  debugPrint('[App] Exiting...');
                  _reminderTimer?.cancel();
                  await windowManager.destroy();
                },
                icon: const Icon(Icons.exit_to_app),
                label: const Text('종료'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
