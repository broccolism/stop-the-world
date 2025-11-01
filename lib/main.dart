import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

Future<void> _checkAccessibilityPermission() async {
  if (Platform.isMacOS) {
    final result = await Process.run(
      'osascript',
      ['-e', 'tell application "System Events" to get UI elements enabled'],
    );

    if ((result.stdout as String).trim() != 'true') {
      debugPrint('[Permission] Accessibility access not enabled.');
      showMacAccessibilityDialog();
    } else {
      debugPrint('[Permission] Accessibility access granted.');
    }
  }
}

void showMacAccessibilityDialog() {
  debugPrint('[Permission] Prompting user to open Accessibility settings...');
  Process.run('open', ['x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility']);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _checkAccessibilityPermission();
  await windowManager.ensureInitialized();

  // 메인 앱용 옵션
  WindowOptions windowOptions = const WindowOptions(
    size: Size(400, 300),
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
    skipTaskbar: false,
    title: 'Reminder',
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

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
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
  int _counter = 0;
  Timer? _popupTimer;
  bool _isPopupShowing = false;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startReminderLoop();
    });
  }

  // 7초마다 팝업 표시
  void _startReminderLoop() {
    Timer.periodic(const Duration(seconds: 7), (timer) async {
      if (_isPopupShowing) {
        debugPrint('[Main] Popup already showing, skipping...');
        return;
      }
      
      debugPrint('[Main] Showing popup...');
      await _showPopup();
    });
  }

  // 팝업을 표시하는 함수
  Future<void> _showPopup() async {
    if (!mounted) return;
    
    _isPopupShowing = true;
    
    // 현재 창 상태 저장
    final currentSize = await windowManager.getSize();
    final currentPosition = await windowManager.getPosition();
    
    // 팝업 오버레이 표시
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: Container(
          color: Colors.black87,
          child: const Center(
            child: Text(
              '🔔 Time to blink!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
    
    try {
      // 최소화되어 있을 수 있으므로 복원
      await windowManager.restore();
      
      // 오버레이 표시
      overlay.insert(overlayEntry);
      
      // 팝업 모드로 전환
      await windowManager.setSize(const Size(300, 100));
      await windowManager.setPosition(const Offset(100, 100));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      await windowManager.focus();
      
      debugPrint('[Popup] Window transformed to popup mode');
      
      // 2초 대기
      await Future.delayed(const Duration(seconds: 2));
      
      // 오버레이 제거
      overlayEntry.remove();
      
      // 원래 상태로 복원
      await windowManager.setSize(currentSize);
      await windowManager.setPosition(currentPosition);
      await windowManager.setAlwaysOnTop(false);
      
      // 창 최소화
      await windowManager.minimize();
      
      debugPrint('[Popup] Window minimized');
    } catch (e) {
      debugPrint('[Popup] Error: $e');
      overlayEntry.remove();
    } finally {
      _isPopupShowing = false;
    }
  }

  @override
  void dispose() {
    _popupTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
