import 'package:flutter/material.dart';
import '../services/pose_service.dart';

class BlacklistPage extends StatefulWidget {
  const BlacklistPage({super.key});

  @override
  State<BlacklistPage> createState() => _BlacklistPageState();
}

class _BlacklistPageState extends State<BlacklistPage> {
  final PoseService _poseService = PoseService();
  List<String> _blockedApps = [];
  final TextEditingController _appNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBlockedApps();
  }

  @override
  void dispose() {
    _appNameController.dispose();
    super.dispose();
  }

  Future<void> _loadBlockedApps() async {
    final apps = await _poseService.loadBlockedApps();
    setState(() {
      _blockedApps = apps;
    });
  }

  Future<void> _addApp() async {
    final appName = _appNameController.text.trim();
    if (appName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('앱 이름을 입력하세요')));
      return;
    }

    if (_blockedApps.contains(appName)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미 등록된 앱입니다')));
      return;
    }

    setState(() {
      _blockedApps.add(appName);
    });
    await _poseService.saveBlockedApps(_blockedApps);
    _appNameController.clear();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('앱이 추가되었습니다')));
    }
  }

  Future<void> _removeApp(String appName) async {
    setState(() {
      _blockedApps.remove(appName);
    });
    await _poseService.saveBlockedApps(_blockedApps);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('앱이 삭제되었습니다')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 설명
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.lightbulb_outline,
                        color: Color(0xFF5B8C85), // 세이지 그린
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('집중 앱이 실행 중일 때는 리마인더가 표시되지 않습니다.', style: const TextStyle(fontSize: 13, color: Color(0xFF424242))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Applications 폴더나 command + tab 으로 조회되는 정확한 앱 이름을 입력해주세요.',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 앱 추가 입력
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _appNameController,
                    decoration: InputDecoration(
                      labelText: '앱 이름 (예: zoom.us, NAVER Whale)',
                      hintText: '앱 번들 ID 또는 프로세스 이름',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => _addApp(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _addApp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5B8C85), // 세이지 그린
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('추가', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 앱 목록
            Text(
              '등록된 앱 (${_blockedApps.length}개)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF424242)),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: _blockedApps.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lightbulb_outline, size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          const Text('등록된 앱이 없습니다', style: TextStyle(fontSize: 16, color: Color(0xFF9E9E9E))),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _blockedApps.length,
                      itemBuilder: (context, index) {
                        final appName = _blockedApps[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0xFFE0E0E0), width: 1),
                          ),
                          child: ListTile(
                            leading: const Icon(
                              Icons.lightbulb,
                              color: Color(0xFF5B8C85), // 세이지 그린
                            ),
                            title: Text(
                              appName,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF424242)),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              color: const Color(0xFF9E9E9E),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('앱 삭제'),
                                    content: Text('$appName을(를) 집중 앱 목록에서 삭제하시겠습니까?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _removeApp(appName);
                                        },
                                        child: const Text('삭제', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
