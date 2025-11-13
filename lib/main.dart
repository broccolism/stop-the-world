import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/settings_page.dart';
import 'pages/reminder_page.dart';
import 'pages/dnd_page.dart';
import 'pages/blacklist_page.dart';
import 'services/pose_service.dart';
import 'models/reminder_type.dart';
import 'widgets/circular_timer_ring.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // 기본 창 설정 - 적당한 크기로 시작
  WindowOptions windowOptions = const WindowOptions(
    size: Size(600, 800),
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.grey,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7F6),
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
  Timer? _countdownTimer; // 카운트다운 표시용 타이머
  bool _isReminderShowing = false;
  bool _isReminderRunning = false; // 리마인더 실행 중 여부
  final PoseService _poseService = PoseService();
  ReminderType _reminderType = ReminderType.poseMatching; // 현재 선택된 리마인더 타입
  int _reminderInterval = 300; // 리마인더 간격 (초, 기본값 5분)
  bool _hasDndSchedule = false; // DND 스케줄 설정 여부
  int _blockedAppsCount = 0; // 집중 앱 개수
  int _remainingSeconds = 0; // 다음 리마인더까지 남은 시간 (초)

  @override
  void initState() {
    super.initState();
    _loadSettings();
    // 자동 시작 제거 - 사용자가 수동으로 시작해야 함
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }
  
  Future<void> _loadSettings() async {
    final type = await _poseService.loadReminderType();
    var interval = await _poseService.loadReminderInterval();
    final hasDnd = await _poseService.hasDndScheduleToday();
    final blockedApps = await _poseService.loadBlockedApps();
    
    // 최소값 보장 (5초)
    if (interval < 5) {
      interval = 5;
      await _poseService.saveReminderInterval(interval);
    }
    
    setState(() {
      _reminderType = type;
      _reminderInterval = interval;
      _hasDndSchedule = hasDnd;
      _blockedAppsCount = blockedApps.length;
    });
  }

  // 시간 포맷팅 (초 -> MM:SS)
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  // 카운트다운 타이머 시작
  void _startCountdown() {
    _remainingSeconds = _reminderInterval;
    
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        // 0에 도달하면 다시 리셋 (다음 주기 시작)
        setState(() {
          _remainingSeconds = _reminderInterval;
        });
      }
    });
  }
  
  // 카운트다운 타이머 중지
  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    setState(() {
      _remainingSeconds = 0;
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
    
    // 카운트다운 시작
    _startCountdown();
    
    debugPrint('[Reminder] Starting reminder loop');
    _startReminderLoop();
  }
  
  // 리마인더 일시중단
  void _pauseReminder() {
    _reminderTimer?.cancel();
    _reminderTimer = null;
    
    // 카운트다운 중지
    _stopCountdown();
    
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
  Future<bool> _isBlockedAppRunning() async {
    try {
      final blockedApps = await _poseService.loadBlockedApps();
      if (blockedApps.isEmpty) return false;

      // ps 명령어로 실행 중인 프로세스 확인
      final result = await Process.run('ps', ['-ax', '-o', 'comm']);
      if (result.exitCode != 0) {
        debugPrint('[Blacklist] Failed to get process list: ${result.stderr}');
        return false;
      }

      final processes = result.stdout.toString().toLowerCase();
      
      for (final appName in blockedApps) {
        if (processes.contains(appName.toLowerCase())) {
          debugPrint('[Blacklist] Blocked app is running: $appName');
          return true;
        }
      }
      
      return false;
    } catch (e) {
      debugPrint('[Blacklist] Error checking blocked apps: $e');
      return false;
    }
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
      
      // DND 체크
      if (await _poseService.isInDndPeriod()) {
        debugPrint('[Reminder] In DND period, skipping reminder...');
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
      
      // 설정 페이지로 이동
      if (mounted) {
        await Navigator.pushNamed(context, '/settings');
      }
      
      debugPrint('[Settings] Settings page closed');
      
      // 자세 설정 완료 후에도 자동 시작하지 않음 (사용자가 수동으로 시작)
      
    } catch (e, stackTrace) {
      debugPrint('[Settings] Error: $e');
      debugPrint('[Settings] Stack trace: $stackTrace');
    }
  }

  // DND 설정 페이지 표시
  Future<void> _showDndSettings() async {
    if (!mounted) return;
    
    try {
      debugPrint('[DND] Showing DND settings page');
      
      // DND 설정 페이지로 이동
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const DndPage()),
        );
      }
      
      debugPrint('[DND] DND settings page closed');
      
      // DND 설정 상태 새로고침
      await _loadSettings();
      
    } catch (e, stackTrace) {
      debugPrint('[DND] Error: $e');
      debugPrint('[DND] Stack trace: $stackTrace');
    }
  }

  // 블랙리스트 설정 페이지 표시
  Future<void> _showBlacklistSettings() async {
    if (!mounted) return;
    
    try {
      debugPrint('[Blacklist] Showing blacklist settings page');
      
      // 블랙리스트 설정 페이지로 이동
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const BlacklistPage()),
        );
      }
      
      debugPrint('[Blacklist] Blacklist settings page closed');
      
      // 집중 앱 목록 다시 로드
      if (mounted) {
        final blockedApps = await _poseService.loadBlockedApps();
        setState(() {
          _blockedAppsCount = blockedApps.length;
        });
      }
      
    } catch (e, stackTrace) {
      debugPrint('[Blacklist] Error: $e');
      debugPrint('[Blacklist] Stack trace: $stackTrace');
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Color(0xFF424242),
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF757575)),
            tooltip: '종료',
            onPressed: () async {
              debugPrint('[App] Exiting...');
              _reminderTimer?.cancel();
              await windowManager.destroy();
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  // 상단: 타이틀 + 리마인더 타입
                  Column(
                    children: [
                      const SizedBox(height: 20),
                      const Text(
                        'Posture Reminder',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF424242),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _reminderType.description,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF757575),
                        ),
                      ),
                    ],
                  ),
                  
                  // 중앙: 원형 타이머 링
                  CircularTimerRing(
                    isRunning: _isReminderRunning,
                    intervalSeconds: _reminderInterval,
                    remainingSeconds: _remainingSeconds,
                    onIntervalChanged: (int newInterval) async {
                      setState(() {
                        _reminderInterval = newInterval;
                      });
                      await _poseService.saveReminderInterval(newInterval);
                    },
                    onStartStop: () {
                      if (_isReminderRunning) {
                        _pauseReminder();
                      } else {
                        _startReminder();
                      }
                    },
                  ),
                  
                  // 하단: 버튼들
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      children: [
                        // 리마인더 타입 선택
                        Opacity(
                          opacity: _isReminderRunning ? 0.5 : 1.0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE0E0E0),
                                width: 1,
                              ),
                            ),
                            child: DropdownButton<ReminderType>(
                              value: _reminderType,
                              underline: Container(),
                              isExpanded: true,
                              icon: Icon(
                                Icons.arrow_drop_down,
                                color: _isReminderRunning ? const Color(0xFFBDBDBD) : const Color(0xFF757575),
                              ),
                              dropdownColor: Colors.white,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _isReminderRunning ? const Color(0xFFBDBDBD) : const Color(0xFF424242),
                              ),
                              disabledHint: Row(
                                children: [
                                  Icon(
                                    _reminderType == ReminderType.poseMatching
                                        ? Icons.accessibility_new
                                        : Icons.remove_red_eye,
                                    color: const Color(0xFFBDBDBD),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _reminderType.displayName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFBDBDBD),
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
                                        color: const Color(0xFF757575),
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
                        
                        // 3개 버튼 가로 배치
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                            // 1. 모드별 설정 버튼
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _showSettings,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE8E8E8),
                                  foregroundColor: const Color(0xFF424242),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _reminderType == ReminderType.poseMatching
                                          ? Icons.camera_alt
                                          : Icons.remove_red_eye,
                                      size: 20,
                                      color: const Color(0xFF757575),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _reminderType == ReminderType.poseMatching
                                          ? '자세 설정'
                                          : '횟수 설정',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            
                            // 2. 방해 금지 모드 버튼
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _showDndSettings,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _hasDndSchedule
                                      ? const Color(0xFFE8A87C)  // 피치 (활성화 시 포인트)
                                      : const Color(0xFFE8E8E8),  // 회색 (비활성화)
                                  foregroundColor: _hasDndSchedule
                                      ? Colors.white
                                      : const Color(0xFF424242),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.schedule,
                                      size: 20,
                                      color: _hasDndSchedule
                                          ? Colors.white
                                          : const Color(0xFF757575),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '방해 금지\n모드',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _hasDndSchedule
                                            ? Colors.white
                                            : const Color(0xFF424242),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            
                            // 3. 집중 앱 버튼
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _showBlacklistSettings,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _blockedAppsCount > 0
                                      ? const Color(0xFF5B8C85)  // 세이지 그린 (설정됨)
                                      : const Color(0xFFE8E8E8),  // 회색 (비활성화)
                                  foregroundColor: _blockedAppsCount > 0
                                      ? Colors.white
                                      : const Color(0xFF424242),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.lightbulb,
                                      size: 20,
                                      color: _blockedAppsCount > 0
                                          ? Colors.white
                                          : const Color(0xFF757575),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _blockedAppsCount > 0
                                          ? '집중 앱\n($_blockedAppsCount개)'
                                          : '집중 앱',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _blockedAppsCount > 0
                                            ? Colors.white
                                            : const Color(0xFF424242),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        ),
                        
                        // DND 스케줄 요약
                        if (_hasDndSchedule)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: FutureBuilder(
                              future: _poseService.loadDndSchedule(),
                              builder: (context, snapshot) {
                                if (snapshot.hasData && snapshot.data != null) {
                                  final schedule = snapshot.data!;
                                  if (schedule.timeRanges.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  final summary = schedule.timeRanges
                                      .map((r) => r.displayText)
                                      .join(', ');
                                  return Text(
                                    summary,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF9E9E9E),
                                    ),
                                    textAlign: TextAlign.center,
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                        
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
