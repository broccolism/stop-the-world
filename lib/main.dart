import 'dart:io'; // 추가
import 'dart:math'; // 팝업 위치 랜덤
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:async';
import 'package:path/path.dart' as path;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  if (args.contains('--popup')) {
    await windowManager.setAsFrameless();
    await windowManager.setSize(const Size(300, 100));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);

    final bounds = await windowManager.getBounds();
    final screenWidth = bounds.width;
    final screenHeight = bounds.height;
    final rand = Random();
    final x = rand.nextInt((screenWidth - 300).toInt()).toDouble();
    final y = rand.nextInt((screenHeight - 100).toInt()).toDouble();

    await windowManager.setPosition(Offset(x, y));
    await windowManager.show();

    runApp(const PopupApp());

    await Future.delayed(const Duration(seconds: 2));
    await windowManager.close();
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
    Timer.periodic(const Duration(seconds: 7), (timer) {
      Process.start(
        _getExecutablePath(),
        ['--popup'],
      );
    });
  }

String _getExecutablePath() {
  final currentAppPath = Platform.executable; // Full path to current executable
  final execFile = File(currentAppPath);
  return path.joinAll([
    execFile.parent.path,
    'stop_the_world',
  ]);
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
