import 'dart:math';
import 'package:flutter/material.dart';

class CircularTimerRing extends StatefulWidget {
  final bool isRunning;
  final int intervalSeconds;
  final int remainingSeconds;
  final bool isDndActive;
  final String? dndTimeRange;
  final ValueChanged<int> onIntervalChanged;
  final VoidCallback onStartStop;

  const CircularTimerRing({
    super.key,
    required this.isRunning,
    required this.intervalSeconds,
    required this.remainingSeconds,
    required this.isDndActive,
    this.dndTimeRange,
    required this.onIntervalChanged,
    required this.onStartStop,
  });

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
    600,    // 10분
    1200,   // 20분
    1800,   // 30분
    2700,   // 45분
    3600,   // 1시간
  ];

  // 시간(초) → 각도 변환 (0도 = 위, 시계방향)
  // 8개를 균등하게 360도에 분산
  double _secondsToAngle(int seconds) {
    final index = _availableIntervals.indexOf(seconds);
    if (index == -1) return 0;
    return ((index + 1) / _availableIntervals.length) * 360;
  }

  // 각도 → 시간(초) 변환
  int _angleToSeconds(double angle) {
    final normalized = (angle % 360) / 360;
    final index = ((normalized * _availableIntervals.length).round() - 1).clamp(0, _availableIntervals.length - 1);
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
    if (widget.isRunning || widget.isDndActive) return; // 실행 중이거나 DND 활성 시 드래그 비활성화

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
      cursor: (widget.isRunning || widget.isDndActive) ? SystemMouseCursors.basic : SystemMouseCursors.click,
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
          isDndActive: widget.isDndActive,
        ),
        child: SizedBox(
          width: 320,
          height: 320,
          child: Center(
            child: widget.isDndActive
                ? _buildDndDisplay()
                : _buildNormalDisplay(),
          ),
        ),
      ),
      ),
    );
  }

  // DND 활성 시 표시
  Widget _buildDndDisplay() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.bedtime,
          size: 72,
          color: Color(0xFF5B8C85),
        ),
        const SizedBox(height: 16),
        const Text(
          '방해금지',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFF424242),
          ),
        ),
        if (widget.dndTimeRange != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.dndTimeRange!,
            style: const TextStyle(
              fontSize: 18,
              color: Color(0xFF757575),
              letterSpacing: 1,
            ),
          ),
        ],
      ],
    );
  }

  // 일반 상태 표시
  Widget _buildNormalDisplay() {
    return Column(
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
            color: Color(0xFF5B8C85),  // 세이지 그린
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 20),
        // 시작/중지 아이콘 버튼
        GestureDetector(
          onTap: widget.onStartStop,
          child: Icon(
            widget.isRunning ? Icons.pause_circle_outline : Icons.play_circle_outline,
            color: widget.isRunning ? const Color(0xFFBDBDBD) : const Color(0xFF5B8C85),  // 회색/세이지 그린
            size: 60,
          ),
        ),
      ],
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
  final bool isDndActive;

  CircularTimerPainter({
    required this.isRunning,
    required this.intervalSeconds,
    required this.remainingSeconds,
    required this.isDndActive,
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

    // 눈금 그리기 (8개의 간격을 균등하게 분산)
    const tickCount = 8;
    final tickPaint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < tickCount; i++) {
      // 각 눈금을 360도에 균등하게 배치 (i+1로 시작)
      final angle = -pi / 2 + ((i + 1) / tickCount) * 2 * pi;
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

    // 2. 진행 링 (DND 활성 시 회색, 아니면 세이지 그린)
    final progressPaint = Paint()
      ..color = isDndActive 
          ? const Color(0xFFBDBDBD)  // DND 활성 시 회색
          : const Color(0xFF5B8C85)  // 세이지 그린
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // 현재 간격에 해당하는 최대 각도 계산
    final intervals = [5, 10, 60, 600, 1200, 1800, 2700, 3600];
    final index = intervals.indexOf(intervalSeconds);
    final maxAngle = ((index + 1) / intervals.length) * 2 * pi;

    double sweepAngle;
    if (isRunning) {
      // 실행 중: 최대 각도 내에서 남은 시간 비율
      sweepAngle = maxAngle * (remainingSeconds / intervalSeconds);
    } else {
      // 중지: 설정한 간격에 해당하는 각도만큼 채움
      sweepAngle = maxAngle;
    }

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2, // 12시 방향부터 시작
      sweepAngle,
      false,
      progressPaint,
    );

    // 3. 드래그 핸들 (실행 중이 아니고 DND 비활성일 때만 표시)
    if (!isRunning && !isDndActive) {
      // 핸들 위치: 현재 간격에 해당하는 각도
      final intervals = [5, 10, 60, 600, 1200, 1800, 2700, 3600];
      final index = intervals.indexOf(intervalSeconds);
      final normalized = (index + 1) / intervals.length;
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

      // 핸들 테두리 (세이지 그린)
      final handleBorderPaint = Paint()
        ..color = const Color(0xFF5B8C85)  // 세이지 그린
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;

      canvas.drawCircle(handleCenter, 15, handleBorderPaint);
    }
  }

  @override
  bool shouldRepaint(CircularTimerPainter oldDelegate) {
    return oldDelegate.isRunning != isRunning ||
        oldDelegate.intervalSeconds != intervalSeconds ||
        oldDelegate.remainingSeconds != remainingSeconds ||
        oldDelegate.isDndActive != isDndActive;
  }
}

