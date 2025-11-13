import 'package:flutter/material.dart';
import '../services/pose_service.dart';

class BlacklistPage extends StatefulWidget {
  const BlacklistPage({Key? key}) : super(key: key);

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('앱 이름을 입력하세요')),
      );
      return;
    }

    if (_blockedApps.contains(appName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 등록된 앱입니다')),
      );
      return;
    }

    setState(() {
      _blockedApps.add(appName);
    });
    await _poseService.saveBlockedApps(_blockedApps);
    _appNameController.clear();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('앱이 추가되었습니다')),
      );
    }
  }

  Future<void> _removeApp(String appName) async {
    setState(() {
      _blockedApps.remove(appName);
    });
    await _poseService.saveBlockedApps(_blockedApps);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('앱이 삭제되었습니다')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('블랙리스트 앱 관리'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 설명
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.orange[700],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '블랙리스트에 등록된 앱이 실행 중일 때는 리마인더가 표시되지 않습니다.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Applications 폴더나 command + tab 으로 조회되는 정확한 앱 이름을 입력해주세요.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _addApp(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _addApp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '추가',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 앱 목록
            Text(
              '등록된 앱 (${_blockedApps.length}개)',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: _blockedApps.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.block,
                            size: 64,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '등록된 앱이 없습니다',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _blockedApps.length,
                      itemBuilder: (context, index) {
                        final appName = _blockedApps[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              Icons.block,
                              color: Colors.red[400],
                            ),
                            title: Text(
                              appName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              color: Colors.red[400],
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('앱 삭제'),
                                    content: Text('$appName을(를) 블랙리스트에서 삭제하시겠습니까?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('취소'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _removeApp(appName);
                                        },
                                        child: const Text(
                                          '삭제',
                                          style: TextStyle(color: Colors.red),
                                        ),
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

