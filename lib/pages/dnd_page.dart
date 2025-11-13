import 'package:flutter/material.dart';
import '../services/pose_service.dart';
import '../models/dnd_schedule.dart';

class DndPage extends StatefulWidget {
  const DndPage({super.key});

  @override
  State<DndPage> createState() => _DndPageState();
}

class _DndPageState extends State<DndPage> {
  final PoseService _poseService = PoseService();
  
  // 48개 슬롯 (0시 0분부터 23시 30분까지 30분 단위)
  List<bool> _selectedSlots = List<bool>.filled(48, false);
  
  // 드래그 관련
  bool _isDragging = false;
  bool? _dragSelectionMode; // true = 선택, false = 해제
  
  final DateTime _today = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }
  
  String _getFormattedDate() {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[_today.weekday - 1];
    return '${_today.year}년 ${_today.month}월 ${_today.day}일 ($weekday)';
  }

  Future<void> _loadSchedule() async {
    final schedule = await _poseService.loadDndSchedule();
    if (schedule != null && schedule.isToday()) {
      setState(() {
        _selectedSlots = DndSchedule.timeRangesToSlots(schedule.timeRanges);
      });
    }
  }

  Future<void> _saveSchedule() async {
    final timeRanges = DndSchedule.slotsToTimeRanges(_selectedSlots);
    
    if (timeRanges.isEmpty) {
      // 시간 범위가 비어있으면 스케줄 삭제
      await _poseService.clearDndSchedule();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('방해 금지 시간이 해제되었습니다'),
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    } else {
      // 시간 범위가 있으면 저장
      final schedule = DndSchedule(
        date: _today,
        timeRanges: timeRanges,
      );
      
      await _poseService.saveDndSchedule(schedule);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('방해 금지 시간이 저장되었습니다'),
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  void _toggleSlot(int index) {
    setState(() {
      _selectedSlots[index] = !_selectedSlots[index];
    });
  }

  void _onSlotDragStart(int index) {
    setState(() {
      _isDragging = true;
      _dragSelectionMode = !_selectedSlots[index]; // 현재 상태의 반대로 드래그
      _selectedSlots[index] = _dragSelectionMode!;
    });
  }

  void _onSlotDragUpdate(int index) {
    if (_isDragging && _dragSelectionMode != null) {
      setState(() {
        _selectedSlots[index] = _dragSelectionMode!;
      });
    }
  }

  void _onSlotDragEnd() {
    setState(() {
      _isDragging = false;
      _dragSelectionMode = null;
    });
  }

  String _getTimeRangesSummary() {
    final timeRanges = DndSchedule.slotsToTimeRanges(_selectedSlots);
    if (timeRanges.isEmpty) {
      return '선택된 시간 없음';
    }
    return timeRanges.map((r) => r.displayText).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final dateString = _getFormattedDate();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF757575)),
        title: const Text(
          '방해 금지 모드',
          style: TextStyle(
            color: Color(0xFF424242),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // 상단: 날짜 표시
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFFE0E0E0),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      color: Color(0xFF5B8C85),  // 세이지 그린
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dateString,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF424242),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '방해 금지 시간대를 선택하세요',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF757575),
                  ),
                ),
              ],
            ),
          ),
          
          // 중간: 시간표
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFE0E0E0),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.touch_app, size: 18, color: Color(0xFF5B8C85)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '리마인드를 받지 않을 시간대를 선택하세요',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF757575),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildTimeGrid(),
                ],
              ),
            ),
          ),
          
          // 하단: 선택된 시간대 요약 및 저장 버튼
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFE0E0E0),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '선택된 시간대',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF757575),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getTimeRangesSummary(),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF424242),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _selectedSlots = List<bool>.filled(48, false);
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF757575),
                          side: const BorderSide(color: Color(0xFFE0E0E0)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text(
                          '모두 해제',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _saveSchedule,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE8A87C),  // 피치 (포인트 컬러)
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                        ),
                        child: const Text(
                          '저장',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeGrid() {
    return Column(
      children: List.generate(24, (hour) {
        return _buildHourRow(hour);
      }),
    );
  }

  Widget _buildHourRow(int hour) {
    final slot1 = hour * 2; // XX:00
    final slot2 = hour * 2 + 1; // XX:30
    
    return Column(
      children: [
        // XX:00 슬롯
        Row(
          children: [
            SizedBox(
              width: 60,
              child: Text(
                '${hour.toString().padLeft(2, '0')}:00',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF424242),
                ),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _buildTimeSlot(slot1, '${hour.toString().padLeft(2, '0')}:00')),
          ],
        ),
        // XX:30 슬롯
        Row(
          children: [
            SizedBox(
              width: 60,
              child: Text(
                '${hour.toString().padLeft(2, '0')}:30',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF9E9E9E),
                ),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _buildTimeSlot(slot2, '${hour.toString().padLeft(2, '0')}:30')),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeSlot(int index, String timeLabel) {
    final isSelected = _selectedSlots[index];

    return GestureDetector(
      onTapDown: (_) => _onSlotDragStart(index),
      onVerticalDragStart: (_) => _onSlotDragStart(index),
      onVerticalDragUpdate: (details) {
        // 드래그 중인 위치의 슬롯 찾기
        final RenderBox box = context.findRenderObject() as RenderBox;
        final localPosition = box.globalToLocal(details.globalPosition);
        
        // 대략적인 슬롯 계산 (각 슬롯 높이는 40px)
        final slotHeight = 40.0;
        final headerHeight = 140.0; // 상단 날짜 표시 영역
        final estimatedSlot = ((localPosition.dy - headerHeight) / slotHeight).floor();
        
        if (estimatedSlot >= 0 && estimatedSlot < 48) {
          _onSlotDragUpdate(estimatedSlot);
        }
      },
      onVerticalDragEnd: (_) => _onSlotDragEnd(),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: isSelected 
              ? const Color(0xFFE8A87C)  // 피치 (포인트 컬러)
              : const Color(0xFFF5F5F5),  // 연한 회색
          border: Border.all(
            color: isSelected
                ? const Color(0xFFE8A87C)
                : const Color(0xFFE0E0E0),
            width: 0.5,
          ),
        ),
        alignment: Alignment.center,
        child: isSelected
            ? const Icon(
                Icons.check,
                size: 16,
                color: Colors.white,
              )
            : null,
      ),
    );
  }
}

