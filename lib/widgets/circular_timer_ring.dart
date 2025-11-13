import 'dart:math';
import 'package:flutter/material.dart';

class CircularTimerRing extends StatefulWidget {
  final bool isRunning;
  final int intervalSeconds;
  final int remainingSeconds;
  final ValueChanged<int> onIntervalChanged;
  final VoidCallback onStartStop;

  const CircularTimerRing({
    Key? key,
    required this.isRunning,
    required this.intervalSeconds,
    required this.remainingSeconds,
    required this.onIntervalChanged,
    required this.onStartStop,
  }) : super(key: key);

  @override
  State<CircularTimerRing> createState() => _CircularTimerRingState();
}

class _CircularTimerRingState extends State<CircularTimerRing> {
  double _currentAngle = 0;

  @override
  void initState() {
    super.initState();
    _currentAngle = _secondsToAngle(widget.intervalSeconds);
  }

  @override
  void didUpdateWidget(CircularTimerRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intervalSeconds != widget.intervalSeconds) {
      _currentAngle = _secondsToAngle(widget.intervalSeconds);
    }
  }

  // 사용 가능한 간격 옵션 (초 단위) - 테스트용
  static const List<int> _availableIntervals = [
    5,      // 5초
    10,     // 10초
    60,     // 1분
    120,    // 2분
    180,    // 3분
  ];

  // 시간(초) → 각도 변환 (0도 = 위, 시계방향)
  // 5개를 균등하게 360도에 분산 (0도, 72도, 144도, 216도, 288도)
  double _secondsToAngle(int seconds) {
    final index = _availableIntervals.indexOf(seconds);
    if (index == -1) return 0;
    return (index / _availableIntervals.length) * 360;
  }

  // 각도 → 시간(초) 변환
  int _angleToSeconds(double angle) {
    final normalized = (angle % 360) / 360;
    final index = (normalized * _availableIntervals.length).round() % _availableIntervals.length;
    return _availableIntervals[index];
  }

  // 터치 좌표 → 각도 변환
  double _positionToAngle(Offset position, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = position.dx - center.dx;
    final dy = position.dy - center.dy;
    // atan2는 -π ~ π 범위, 0도를 위쪽으로 조정
    var angle = atan2(dx, -dy) * 180 / pi;
    if (angle < 0) angle += 360;
    return angle;
  }

  void _handleDragUpdate(DragUpdateDetails details, Size size) {
    if (widget.isRunning) return; // 실행 중에는 드래그 비활성화

    final angle = _positionToAngle(details.localPosition, size);
    final seconds = _angleToSeconds(angle);

    if (seconds != widget.intervalSeconds) {
      widget.onIntervalChanged(seconds);
    }
  }

  String _formatTime(int seconds) {
    if (seconds < 60) {
      return '$seconds초';
    }
    final minutes = seconds ~/ 60;
    if (minutes >= 60) {
      return '${minutes ~/ 60}시간';
    }
    return '$minutes분';
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.isRunning ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onPanUpdate: (details) {
          final RenderBox renderBox = context.findRenderObject() as RenderBox;
          _handleDragUpdate(details, renderBox.size);
        },
        child: CustomPaint(
        size: const Size(320, 320),
        painter: CircularTimerPainter(
          isRunning: widget.isRunning,
          intervalSeconds: widget.intervalSeconds,
          remainingSeconds: widget.remainingSeconds,
        ),
        child: SizedBox(
          width: 320,
          height: 320,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 시간 표시
                Text(
                  widget.isRunning
                      ? _formatCountdown(widget.remainingSeconds)
                      : _formatTime(widget.intervalSeconds),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 20),
                // 시작/중지 아이콘 버튼
                GestureDetector(
                  onTap: widget.onStartStop,
                  child: Icon(
                    widget.isRunning ? Icons.pause_circle_outline : Icons.play_circle_outline,
                    color: widget.isRunning ? Colors.grey : Colors.deepPurple,
                    size: 60,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  String _formatCountdown(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

class CircularTimerPainter extends CustomPainter {
  final bool isRunning;
  final int intervalSeconds;
  final int remainingSeconds;

  CircularTimerPainter({
    required this.isRunning,
    required this.intervalSeconds,
    required this.remainingSeconds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 30; // 핸들 공간 확보
    const strokeWidth = 22.0;

    // 1. 배경 링 (연한 회색)
    final backgroundPaint = Paint()
      ..color = Colors.grey[200]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    // 1.5. 눈금 표시용 안쪽 원 (얇은 회색 선)
    final tickCircleRadius = radius - strokeWidth - 10; // 링보다 안쪽
    final tickCirclePaint = Paint()
      ..color = Colors.grey[300]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, tickCircleRadius, tickCirclePaint);

    // 눈금 그리기 (5개의 간격을 균등하게 분산)
    const tickCount = 5;
    final tickPaint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < tickCount; i++) {
      // 각 눈금을 360도에 균등하게 배치
      final angle = -pi / 2 + (i / tickCount) * 2 * pi;
      final tickStartRadius = tickCircleRadius - 8;
      final tickEndRadius = tickCircleRadius + 8;
      
      final startX = center.dx + tickStartRadius * cos(angle);
      final startY = center.dy + tickStartRadius * sin(angle);
      final endX = center.dx + tickEndRadius * cos(angle);
      final endY = center.dy + tickEndRadius * sin(angle);
      
      canvas.drawLine(
        Offset(startX, startY),
        Offset(endX, endY),
        tickPaint,
      );
    }

    // 2. 진행 링 (보라색)
    final progressPaint = Paint()
      ..color = Colors.deepPurple
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    double sweepAngle;
    if (isRunning) {
      // 실행 중: 남은 시간 비율
      sweepAngle = (remainingSeconds / intervalSeconds) * 2 * pi;
    } else {
      // 중지: 100% 채움
      sweepAngle = 2 * pi;
    }

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2, // 12시 방향부터 시작
      sweepAngle,
      false,
      progressPaint,
    );

    // 3. 드래그 핸들 (실행 중이 아닐 때만 표시)
    if (!isRunning) {
      // 핸들 위치: 현재 간격에 해당하는 각도
      final intervals = [5, 10, 60, 120, 180];
      final index = intervals.indexOf(intervalSeconds);
      final normalized = index / intervals.length;
      final handleAngle = -pi / 2 + (normalized * 2 * pi);

      final handleX = center.dx + radius * cos(handleAngle);
      final handleY = center.dy + radius * sin(handleAngle);
      final handleCenter = Offset(handleX, handleY);

      // 핸들 그림자
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

      canvas.drawCircle(handleCenter, 16, shadowPaint);

      // 핸들 배경 (흰색)
      final handleBackgroundPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      canvas.drawCircle(handleCenter, 15, handleBackgroundPaint);

      // 핸들 테두리 (보라색)
      final handleBorderPaint = Paint()
        ..color = Colors.deepPurple
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;

      canvas.drawCircle(handleCenter, 15, handleBorderPaint);
    }
  }

  @override
  bool shouldRepaint(CircularTimerPainter oldDelegate) {
    return oldDelegate.isRunning != isRunning ||
        oldDelegate.intervalSeconds != intervalSeconds ||
        oldDelegate.remainingSeconds != remainingSeconds;
  }
}

