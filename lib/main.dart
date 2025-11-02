import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  // 7초마다 창을 최상단에 표시, 2초 후 최소화
  void _startReminderLoop() {
    Timer.periodic(const Duration(seconds: 7), (timer) async {
      if (_isPopupShowing) {
        debugPrint('[Reminder] Already showing, skipping...');
        return;
      }
      
      debugPrint('[Reminder] Showing window...');
      await _showReminder();
    });
  }

  // 알림 창을 표시하는 함수
  Future<void> _showReminder() async {
    if (!mounted) return;
    
    _isPopupShowing = true;
    
    try {
      // 최소화되어 있으면 복원
      await windowManager.restore();
      
      // 최상단으로 올리고 포커스 주기
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      await windowManager.focus();
      
      debugPrint('[Reminder] Window shown on top');
      
      // 2초 대기
      await Future.delayed(const Duration(seconds: 2));
      
      // 최상단 해제 후 최소화
      await windowManager.setAlwaysOnTop(false);
      await windowManager.minimize();
      
      debugPrint('[Reminder] Window minimized');
    } catch (e) {
      debugPrint('[Reminder] Error: $e');
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
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Exit App',
            onPressed: () async {
              debugPrint('[App] Exiting...');
              _popupTimer?.cancel();
              await windowManager.destroy();
            },
          ),
        ],
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
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () async {
                debugPrint('[App] Exiting...');
                _popupTimer?.cancel();
                await windowManager.destroy();
              },
              icon: const Icon(Icons.exit_to_app),
              label: const Text('Exit App'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
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
