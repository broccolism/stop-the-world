import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/settings_page.dart';
import 'pages/reminder_page.dart';
import 'services/pose_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // 메인 앱용 옵션
  WindowOptions windowOptions = const WindowOptions(
    size: Size(500, 480),
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

  // TODO: 나중에 UI에서 편집 가능하게 변경 예정
  final List<String> _blockedApps = ['zoom.us']; // Zoom 앱

  @override
  void initState() {
    super.initState();
    // 자동 시작 제거 - 사용자가 수동으로 시작해야 함
  }

  // 리마인더 시작
  Future<void> _startReminder() async {
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
  
  // 다음 리마인더 예약 (20초 후)
  void _scheduleNextReminder() {
    if (!_isReminderRunning) {
      debugPrint('[Reminder] Loop stopped, not scheduling next reminder');
      return;
    }
    
    debugPrint('[Reminder] Scheduling next reminder in 20 seconds...');
    _reminderTimer = Timer(const Duration(seconds: 20), () async {
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
              const Text(
                '올바른 자세를 유지하세요!',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 30),
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
              const SizedBox(height: 16),
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
