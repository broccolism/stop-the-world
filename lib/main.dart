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

  // 기본 창 설정 - 데스크톱 앱 비율 (가로가 더 긴 레이아웃)
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1100, 650),  // 약 17:10 비율
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
    skipTaskbar: false,
    title: 'pause!',
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
      title: 'pause!',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.grey,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7F6),
      ),
      home: const MyHomePage(title: 'pause!'),
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
  int _reminderInterval = 5; // 리마인더 간격 (초, 기본값 5분)
  bool _hasDndSchedule = false; // DND 스케줄 설정 여부
  int _blockedAppsCount = 0; // 집중 앱 개수
  int _remainingSeconds = 0; // 다음 리마인더까지 남은 시간 (초)
  int _selectedIndex = 0; // 현재 선택된 페이지 인덱스 (0: 홈, 1: 설정, 2: DND, 3: 집중 앱)
  bool _isDndActive = false; // 현재 DND가 활성화되었는지 여부
  String? _dndTimeRange; // DND 시간대 (예: "14:00 - 15:30")

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _updateDockIcon(); // 초기 아이콘 설정
    // 카메라 권한은 실제 사용 시 자동으로 요청됨
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
    final isDndActive = await _poseService.isInDndPeriod();
    final dndTimeRange = await _poseService.getDndTimeRange();
    
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
      _isDndActive = isDndActive;
      _dndTimeRange = dndTimeRange;
    });
    
    // 설정 로드 후 아이콘 업데이트
    _updateDockIcon();
  }

  // Dock 아이콘 업데이트 - 현재 상태를 표시
  // (DND는 타이머 링에서 표시하므로 dock 아이콘에 영향 없음)
  Future<void> _updateDockIcon() async {
    if (_isReminderRunning) {
      // 리마인더 실행 중 -> 일시정지 아이콘 표시
      await _poseService.setDockIcon('pause');
    } else {
      // 리마인더 중단 중 -> 재생 아이콘 표시
      await _poseService.setDockIcon('play');
    }
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
    
    // Dock 아이콘 업데이트 (일시중단 아이콘)
    await _updateDockIcon();
    
    debugPrint('[Reminder] Starting reminder loop');
    _startReminderLoop();
    // 카운트다운은 _scheduleNextReminder()에서 시작됨
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
    
    // Dock 아이콘 업데이트 (재생 아이콘)
    _updateDockIcon();
    
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

      // NSWorkspace API를 사용하여 실행 중인 앱 목록 가져오기
      final runningApps = await _poseService.getRunningApps();
      debugPrint('[Blacklist] Checking ${blockedApps.length} blocked apps against ${runningApps.length} running apps');
      debugPrint('[Blacklist] Blocked apps: $blockedApps');
      debugPrint('[Blacklist] Running apps: $runningApps');
      
      // 블랙리스트 앱과 실행 중인 앱 비교
      for (final blockedApp in blockedApps) {
        final blockedLower = blockedApp.toLowerCase();
        
        for (final runningApp in runningApps) {
          final runningLower = runningApp.toLowerCase();
          
          // 부분 일치 검사 (예: "zoom" -> "Zoom" 또는 "zoom.us" -> "Zoom")
          if (runningLower.contains(blockedLower) || blockedLower.contains(runningLower)) {
            debugPrint('[Blacklist] Blocked app is running: $blockedApp (matched: $runningApp)');
            return true;
          }
        }
      }
      
      debugPrint('[Blacklist] No blocked apps detected');
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
    
    // 카운트다운 시작 (타이머와 함께)
    _startCountdown();
    
    _reminderTimer = Timer(Duration(seconds: _reminderInterval), () async {
      if (!_isReminderRunning || _isReminderShowing) {
        debugPrint('[Reminder] Skipping reminder (running: $_isReminderRunning, showing: $_isReminderShowing)');
        // 리마인더가 이미 표시 중이면 1초 후 재시도 (카운트다운은 시작하지 않음)
        await Future.delayed(const Duration(seconds: 1));
        if (_isReminderRunning && !_isReminderShowing) {
          _scheduleNextReminder();
        }
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
      
      // 리마인더 표시하는 동안 카운트다운 중지
      _stopCountdown();
      
      debugPrint('[Reminder] Showing reminder...');
      await _showReminder();
      
      // 리마인더가 닫힌 후 다음 리마인더 예약 (이때 카운트다운 다시 시작)
      debugPrint('[Reminder] Reminder closed, scheduling next one');
      _scheduleNextReminder();
    });
  }

  // 페이지 변경 시 설정 다시 로드
  void _onPageChanged(int index) {
    setState(() {
      _selectedIndex = index;
    });
    
    // 홈으로 돌아올 때 설정 새로고침
    if (index == 0) {
      _loadSettings();
    }
    
    // DND 페이지에서 돌아올 때 아이콘 업데이트 (DND 설정이 변경되었을 수 있음)
    if (index == 0) {
      _updateDockIcon();
    }
  }

  // 리마인더 페이지 표시
  Future<void> _showReminder() async {
    if (!mounted) {
      debugPrint('[Reminder] Widget not mounted, aborting');
      return;
    }
    
    // 자세 매칭 모드일 때만 기준 자세 확인
    if (_reminderType == ReminderType.poseMatching) {
      final hasReferencePose = await _hasReferencePose();
      if (!hasReferencePose) {
        debugPrint('[Reminder] No reference pose, skipping reminder');
        return;
      }
    }
    
    _isReminderShowing = true;
    
    try {
      debugPrint('[Reminder] Starting window manager operations...');
      
      // 최소화되어 있으면 복원
      try {
        debugPrint('[Reminder] Restoring window...');
        await windowManager.restore();
        await Future.delayed(const Duration(milliseconds: 100));
        debugPrint('[Reminder] Window restored');
      } catch (e, st) {
        debugPrint('[Reminder] Window restore error: $e');
        debugPrint('[Reminder] Stack: $st');
      }
      
      // 최상단으로 올리고 포커스 주기
      try {
        debugPrint('[Reminder] Setting window always on top...');
        await windowManager.setAlwaysOnTop(true);
        await Future.delayed(const Duration(milliseconds: 50));
        
        debugPrint('[Reminder] Showing window...');
        await windowManager.show();
        await Future.delayed(const Duration(milliseconds: 50));
        
        debugPrint('[Reminder] Focusing window...');
        await windowManager.focus();
        await Future.delayed(const Duration(milliseconds: 100));
        debugPrint('[Reminder] Window focused');
      } catch (e, st) {
        debugPrint('[Reminder] Window focus error: $e');
        debugPrint('[Reminder] Stack: $st');
      }
      
      debugPrint('[Reminder] About to show reminder page...');
      
      // 리마인더 페이지로 이동
      if (!mounted) {
        debugPrint('[Reminder] Widget unmounted before navigation');
        return;
      }
      
      try {
        debugPrint('[Reminder] Calling Navigator.pushNamed...');
        await Navigator.pushNamed(context, '/reminder');
        debugPrint('[Reminder] Navigator.pushNamed completed');
      } catch (e, st) {
        debugPrint('[Reminder] Navigation error: $e');
        debugPrint('[Reminder] Stack: $st');
        return;
      }
      
      debugPrint('[Reminder] Reminder page closed');
      
      // 최상단 해제 후 최소화
      try {
        debugPrint('[Reminder] Removing always on top...');
        await windowManager.setAlwaysOnTop(false);
        await Future.delayed(const Duration(milliseconds: 50));
        
        debugPrint('[Reminder] Minimizing window...');
        await windowManager.minimize();
        debugPrint('[Reminder] Window minimized');
      } catch (e, st) {
        debugPrint('[Reminder] Window minimize error: $e');
        debugPrint('[Reminder] Stack: $st');
      }
      
      debugPrint('[Reminder] Window operations completed');
    } catch (e, stackTrace) {
      debugPrint('[Reminder] Unexpected error: $e');
      debugPrint('[Reminder] Stack trace: $stackTrace');
    } finally {
      _isReminderShowing = false;
    }
  }

  // 홈 화면 위젯 (기존 body 내용)
  Widget _buildHomePage() {
    return LayoutBuilder(
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
                      Text(
                        _reminderType.displayName,
                        style: const TextStyle(
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
                    isDndActive: _isDndActive,
                    dndTimeRange: _dndTimeRange,
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
                  
                  // 하단: 리마인더 타입 선택
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
  }

  // 사이드바 아이콘 반환
  IconData _getSidebarIcon() {
    switch (_reminderType) {
      case ReminderType.poseMatching:
        return Icons.accessibility_new;
      case ReminderType.blinkCount:
        return Icons.remove_red_eye;
    }
  }

  // 사이드바 라벨 반환
  String _getSidebarLabel() {
    switch (_reminderType) {
      case ReminderType.poseMatching:
        return '자세 설정';
      case ReminderType.blinkCount:
        return '횟수 설정';
    }
  }

  // 사이드바 위젯
  Widget _buildSidebar() {
    return Container(
      width: 200,
      color: const Color(0xFFF5F5F5),
      child: Column(
        children: [
          const SizedBox(height: 20),
          _buildSidebarItem(0, Icons.home, '홈'),
          _buildSidebarItem(
            1,
            _getSidebarIcon(),
            _getSidebarLabel(),
          ),
          _buildSidebarItem(2, Icons.schedule, '방해 금지 모드'),
          _buildSidebarItem(3, Icons.lightbulb, '집중 앱'),
        ],
      ),
    );
  }

  // 사이드바 항목 위젯
  Widget _buildSidebarItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => _onPageChanged(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        color: isSelected ? const Color(0xFF5B8C85) : Colors.transparent,
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : const Color(0xFF757575),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF757575),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 선택된 페이지 위젯 반환
  Widget _getSelectedPage() {
    switch (_selectedIndex) {
      case 0:
        return _buildHomePage();
      case 1:
        return const SettingsPage();
      case 2:
        return const DndPage();
      case 3:
        return const BlacklistPage();
      default:
        return _buildHomePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 좌측: 사이드바
          _buildSidebar(),
          // 우측: 선택된 페이지 컨텐츠
          Expanded(
            child: _getSelectedPage(),
          ),
        ],
      ),
    );
  }
}
