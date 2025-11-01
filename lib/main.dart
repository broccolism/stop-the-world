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

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await _checkAccessibilityPermission();
  await windowManager.ensureInitialized();

  if (args.contains('--popup')) {
    debugPrint('[Popup] Initializing popup window...');
    await windowManager.setAsFrameless();
    await windowManager.setSize(const Size(300, 100));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);

    final x = 1.0;
    final y = 1.0;

    await windowManager.setPosition(Offset(x, y));
    await windowManager.show();
    debugPrint('[Popup] Window shown. Running app...');

    runApp(const PopupApp());

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      debugPrint('[Popup] UI rendered, waiting 2 seconds before closing...');
      await Future.delayed(const Duration(seconds: 2));
      debugPrint('[Popup] Closing window...');
      await windowManager.close();
      debugPrint('[Popup] Closed successfully.');
      exit(0);
    });
    return;
  }

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

  // 7초마다 서브 프로세스를 실행
  void _startReminderLoop() {
    Timer.periodic(const Duration(seconds: 7), (timer) async {
      final executablePath = Platform.resolvedExecutable;

      debugPrint('[Popup] Trying to launch executable at: $executablePath');

      final file = File(executablePath);
      if (!file.existsSync()) {
        debugPrint('[Popup] Executable does not exist at path: $executablePath');
        return;
      }

      try {
        final result = await Process.run(executablePath, ['--popup']);
        debugPrint('Popup launched: ${result.stdout}');
        if (result.stderr != null && result.stderr.toString().isNotEmpty) {
          debugPrint('Popup stderr: ${result.stderr}');
        }
      } catch (e, st) {
        debugPrint('Failed to launch popup: $e\n$st');
      }
    });
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

// 팝업 앱
class PopupApp extends StatelessWidget {
  const PopupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black87,
        body: Center(
          child: Text(
            '🔔 Time to blink!',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
      ),
    );
  }
}
