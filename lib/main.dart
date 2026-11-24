import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'data/food_database.dart';
import 'models/food_item.dart';
import 'services/gemini_service.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const FridgePleaseApp());
}

class FridgePleaseApp extends StatelessWidget {
  const FridgePleaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '냉장고를 부탁해',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10B981),
          primary: const Color(0xFF10B981),
          surface: const Color(0xFFF8FAFC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
      ),
      home: const MainHomePage(),
    );
  }
}

class MainHomePage extends StatefulWidget {
  const MainHomePage({super.key});

  @override
  State<MainHomePage> createState() => _MainHomePageState();
}

class _MainHomePageState extends State<MainHomePage> {
  final ImagePicker _picker = ImagePicker();

  int _tabIndex = 0;
  List<FoodItem> _items = [];
  String _apiKey = '';
  int _notifyHour = 17;
  int _notifyMinute = 0;
  int _savedCount = 0;
  int _savedMoney = 0;

  // 홈 필터
  String _statusFilter = 'all'; // all | warn | expired
  String _zoneFilter = 'all'; // all | fridge | freezer | room
  String _searchQuery = '';
  String _sortMode = 'dday'; // dday | recent | name

  // 스캔 / 등록 상태
  String _scanMode = 'fresh'; // fresh | ocr | receipt
  bool _isAnalyzing = false;
  Uint8List? _previewBytes;
  final TextEditingController _regNameCtrl = TextEditingController();
  final TextEditingController _regMemoCtrl = TextEditingController();
  String _regEmoji = '🥬';
  String _regZone = 'fridge';
  String _regStartDate = todayDateStr();
  String _regExpiryDate = addDaysStr(todayDateStr(), 5);
  String _regTip = '품목을 촬영하거나 선택하면 최적의 보관 방법이 자동으로 표시됩니다.';
  String _regBadge = '직접 입력 / 자동 계산';
  bool _regReminder = true;
  FoodPreset? _selectedPreset;

  // 레시피 상태
  final Set<String> _selectedRecipeIds = {};
  String _recipeTime = '25분 내외 집밥';
  String _recipeStyle = '한식 집밥';
  bool _isGeneratingRecipes = false;
  List<RecipeSuggestion> _recipes = [];

  // 가이드 검색
  String _guideSearch = '';

  // 설정 API 키 입력
  final TextEditingController _apiKeyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _regNameCtrl.dispose();
    _regMemoCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    final loadedItems = await StorageService.loadItems();
    final key = await StorageService.loadApiKey();
    final (h, m) = await StorageService.loadNotifyTime();
    final (sCount, sMoney) = await StorageService.loadStats();

    if (!mounted) return;
    setState(() {
      _items = loadedItems;
      _apiKey = key;
      _apiKeyCtrl.text = key;
      _notifyHour = h;
      _notifyMinute = m;
      _savedCount = sCount;
      _savedMoney = sMoney;
      _syncUrgentRecipeSelection();
    });

    await NotificationService.instance.requestPermission();
    await NotificationService.instance.rescheduleAll(_items, _notifyHour, _notifyMinute);
  }

  void _syncUrgentRecipeSelection() {
    _selectedRecipeIds.clear();
    for (final it in _items) {
      if (calcDDay(it.expiryDate) <= 3) {
        _selectedRecipeIds.add(it.id);
      }
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String get _formattedNotifyTime =>
      '${_notifyHour.toString().padLeft(2, '0')}:${_notifyMinute.toString().padLeft(2, '0')}';

  // ==================== 빌드 ====================
  @override
  Widget build(BuildContext context) {
    final warnCount = _items.where((i) {
      final d = calcDDay(i.expiryDate);
      return d >= 0 && d <= 3;
    }).length;
    final expiredCount = _items.where((i) => calcDDay(i.expiryDate) < 0).length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: const Text('🥬', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '냉장고를 부탁해',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                Text(
                  _apiKey.isNotEmpty ? 'Gemini AI 실시간 인식 ON' : '오프라인 표준 DB 모드',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _apiKey.isNotEmpty ? const Color(0xFF059669) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              setState(() {
                _tabIndex = 2;
                _scanMode = 'receipt';
              });
            },
            icon: const Text('🧾'),
            label: const Text('영수증', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: 'D-3 알림 센터',
            onPressed: () => setState(() => _tabIndex = 4),
            icon: Badge(
              isLabelVisible: (warnCount + expiredCount) > 0,
              label: Text('${warnCount + expiredCount}'),
              child: const Icon(Icons.notifications_active_outlined),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _buildHomeTab(warnCount, expiredCount),
          _buildRecipeTab(),
          _buildScanTab(),
          _buildGuideTab(),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) {
          setState(() {
            _tabIndex = idx;
            if (idx == 1 && _selectedRecipeIds.isEmpty) {
              _syncUrgentRecipeSelection();
            }
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.kitchen_outlined), selectedIcon: Icon(Icons.kitchen), label: '내 냉장고'),
          NavigationDestination(icon: Icon(Icons.restaurant_menu_outlined), selectedIcon: Icon(Icons.restaurant_menu), label: '저녁 레시피'),
          NavigationDestination(icon: Icon(Icons.camera_alt_outlined), selectedIcon: Icon(Icons.camera_alt), label: '촬영 등록'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: '보관 가이드'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '알림·설정'),
        ],
      ),
    );
  }

  // ==================== 1. 내 냉장고 탭 ====================
  Widget _buildHomeTab(int warnCount, int expiredCount) {
    final filtered = _items.where((it) {
      final d = calcDDay(it.expiryDate);
      if (_statusFilter == 'warn' && !(d >= 0 && d <= 3)) return false;
      if (_statusFilter == 'expired' && !(d < 0)) return false;
      if (_zoneFilter != 'all' && it.zone != _zoneFilter) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!it.name.toLowerCase().contains(q) && !it.memo.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      if (_sortMode == 'name') return a.name.compareTo(b.name);
      if (_sortMode == 'recent') return b.registeredDate.compareTo(a.registeredDate);
      return calcDDay(a.expiryDate).compareTo(calcDDay(b.expiryDate));
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // 요약 카드 3종
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                label: '전체 식자재',
                count: _items.length,
                active: _statusFilter == 'all',
                activeColor: const Color(0xFF10B981),
                onTap: () => setState(() => _statusFilter = 'all'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                label: '폐기 임박 D-3',
                count: warnCount,
                active: _statusFilter == 'warn',
                activeColor: const Color(0xFFF59E0B),
                onTap: () => setState(() => _statusFilter = 'warn'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                label: '기한 만료',
                count: expiredCount,
                active: _statusFilter == 'expired',
                activeColor: const Color(0xFFEF4444),
                onTap: () => setState(() => _statusFilter = 'expired'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 임박 식자재 구출 배너
        if (warnCount > 0) ...[
          InkWell(
            onTap: () {
              setState(() {
                _syncUrgentRecipeSelection();
                _tabIndex = 1;
              });
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🔥 폐기 임박(D-3 이내) 식자재 $warnCount개 구출하기!',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '버리기 전에 오늘 저녁 메뉴 AI 레시피 확인하기',
                          style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Text('레시피 →', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 보관 구역 필터
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildZoneChip('all', '전체 보관'),
              const SizedBox(width: 6),
              _buildZoneChip('fridge', '❄️ 냉장실'),
              const SizedBox(width: 6),
              _buildZoneChip('freezer', '🧊 냉동실'),
              const SizedBox(width: 6),
              _buildZoneChip('room', '🌡️ 실온'),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 검색 & 정렬
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: '식자재 검색 (예: 시금치, 삼겹살)',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _sortMode,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                  items: const [
                    DropdownMenuItem(value: 'dday', child: Text('임박순')),
                    DropdownMenuItem(value: 'recent', child: Text('최신순')),
                    DropdownMenuItem(value: 'name', child: Text('이름순')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _sortMode = v);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                const Text('🥬', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 8),
                const Text('표시할 식자재가 없습니다', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('하단 [촬영 등록] 탭에서 식자재를 추가해 보세요.', style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => setState(() => _tabIndex = 2),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('식자재 촬영 등록하기'),
                ),
              ],
            ),
          )
        else
          ...filtered.map(_buildFoodCard),
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required int count,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? activeColor : const Color(0xFFE2E8F0), width: 1.5),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: active ? activeColor : const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneChip(String value, String label) {
    final selected = _zoneFilter == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : const Color(0xFF334155))),
      selected: selected,
      selectedColor: const Color(0xFF0F172A),
      backgroundColor: Colors.white,
      showCheckmark: false,
      onSelected: (_) => setState(() => _zoneFilter = value),
    );
  }

  Widget _buildFoodCard(FoodItem item) {
    final dDay = calcDDay(item.expiryDate);
    final isExpired = dDay < 0;
    final isWarn = dDay >= 0 && dDay <= 3;

    final Color badgeBg = isExpired
        ? const Color(0xFFFEF2F2)
        : isWarn
            ? const Color(0xFFFFFBEB)
            : const Color(0xFFECFDF5);
    final Color badgeFg = isExpired
        ? const Color(0xFFB91C1C)
        : isWarn
            ? const Color(0xFFB45309)
            : const Color(0xFF059669);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        onTap: () => _openDetailSheet(item),
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isExpired
                  ? const Color(0xFFFCA5A5)
                  : isWarn
                      ? const Color(0xFFFCD34D)
                      : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(item.emoji, style: const TextStyle(fontSize: 23)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: item.zone == 'freezer'
                                ? const Color(0xFFE0F2FE)
                                : item.zone == 'room'
                                    ? const Color(0xFFF1F5F9)
                                    : const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            zoneLabel(item.zone),
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF1E40AF)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '만료 ${item.expiryDate}${item.memo.isNotEmpty ? ' · ${item.memo}' : ''}${item.reminderEnabled ? ' · 🔔 D-${item.reminderOffset}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 56),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  formatDDayLabel(dDay),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: badgeFg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 식자재 상세 & 냉장↔냉동 자동 전환 바텀시트
  void _openDetailSheet(FoodItem initialItem) {
    FoodItem current = initialItem;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final dDay = calcDDay(current.expiryDate);

            Future<void> saveUpdatedItem(FoodItem updated, {String? toast}) async {
              final idx = _items.indexWhere((e) => e.id == updated.id);
              if (idx != -1) {
                setState(() => _items[idx] = updated);
                setSheetState(() => current = updated);
                await StorageService.saveItems(_items);
                await NotificationService.instance.scheduleForItem(updated, _notifyHour, _notifyMinute);
                if (toast != null) _showSnack(toast);
              }
            }

            Future<void> switchZone(String newZone) async {
              if (current.zone == newZone) return;
              final preset = findPresetByName(current.name);
              final today = todayDateStr();
              final newDays = preset != null
                  ? preset.daysForZone(newZone)
                  : (newZone == 'freezer' ? 30 : newZone == 'room' ? 3 : 5);
              final newTip = preset != null
                  ? preset.tipForZone(newZone)
                  : (newZone == 'freezer'
                      ? '1회 분량씩 소분해 공기를 빼고 밀봉 후 냉동하세요. 조리 하루 전 냉장실 저온 해동을 권장합니다.'
                      : '밀폐용기에 담아 냉장실 안쪽 신선 칸에 보관하세요.');
              final newOffset = newZone == 'freezer' ? 7 : 3;

              final updated = current.copyWith(
                zone: newZone,
                expiryDate: addDaysStr(today, newDays),
                tip: newTip,
                reminderOffset: newOffset,
              );
              await saveUpdatedItem(
                updated,
                toast: '${zoneLabel(newZone)}로 이동되어 기한(+$newDays일)·보관팁·알람(D-$newOffset)이 자동 재계산되었습니다!',
              );
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(18, 12, 18, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(99)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(14)),
                          alignment: Alignment.center,
                          child: Text(current.emoji, style: const TextStyle(fontSize: 25)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(current.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                              Text('등록 ${current.registeredDate} · 만료 ${current.expiryDate}',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: dDay < 0 ? const Color(0xFFFEF2F2) : dDay <= 3 ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            formatDDayLabel(dDay),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: dDay < 0 ? const Color(0xFFB91C1C) : dDay <= 3 ? const Color(0xFFB45309) : const Color(0xFF059669),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('보관 구역 전환 (냉장 ↔ 냉동 전환 시 기한·팁·알람 자동 변경)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildDetailZoneButton('fridge', '❄️ 냉장실', current.zone == 'fridge', () => switchZone('fridge')),
                        const SizedBox(width: 6),
                        _buildDetailZoneButton('freezer', '🧊 냉동실', current.zone == 'freezer', () => switchZone('freezer')),
                        const SizedBox(width: 6),
                        _buildDetailZoneButton('room', '🌡️ 실온', current.zone == 'room', () => switchZone('room')),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Text('섭취 만료일 조정', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: sheetCtx,
                              initialDate: parseDateStr(current.expiryDate),
                              firstDate: DateTime(2024),
                              lastDate: DateTime(2032),
                            );
                            if (picked != null) {
                              await saveUpdatedItem(current.copyWith(expiryDate: formatDate(picked)), toast: '만료일이 수정되었습니다.');
                            }
                          },
                          icon: const Icon(Icons.calendar_today, size: 15),
                          label: Text(current.expiryDate, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    Row(
                      children: [1, 3, 7, 30].map((d) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: OutlinedButton(
                              onPressed: () async {
                                await saveUpdatedItem(
                                  current.copyWith(expiryDate: addDaysStr(current.expiryDate, d)),
                                  toast: '만료일이 +$d일 연장되었습니다.',
                                );
                              },
                              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
                              child: Text('+$d일', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Text(
                        '💡 보관 · 해동 가이드: ${current.tip}',
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF065F46), height: 1.45),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '🔔 만료 ${current.reminderOffset}일 전(D-${current.reminderOffset}) 네이티브 알람',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text('예약 시각: ${addDaysStr(current.expiryDate, -current.reminderOffset)} $_formattedNotifyTime'),
                      value: current.reminderEnabled,
                      onChanged: (val) async {
                        await saveUpdatedItem(current.copyWith(reminderEnabled: val));
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              await NotificationService.instance.cancelForItem(current);
                              setState(() {
                                _items.removeWhere((e) => e.id == current.id);
                                _savedCount += 1;
                                _savedMoney += current.estimatedPrice;
                              });
                              await StorageService.saveItems(_items);
                              await StorageService.saveStats(_savedCount, _savedMoney);
                              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              _showSnack('🎉 ${current.name} 구출 완료! (${formatWon(current.estimatedPrice)} 절약)');
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('소비 완료(구출)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFB91C1C),
                              side: const BorderSide(color: Color(0xFFFCA5A5)),
                            ),
                            onPressed: () async {
                              await NotificationService.instance.cancelForItem(current);
                              setState(() => _items.removeWhere((e) => e.id == current.id));
                              await StorageService.saveItems(_items);
                              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              _showSnack('${current.name} 항목이 삭제되었습니다.');
                            },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('폐기 / 삭제'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailZoneButton(String zone, String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: active ? const Color(0xFF10B981) : const Color(0xFFE2E8F0), width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: active ? const Color(0xFF059669) : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  // ==================== 2. AI 저녁 레시피 탭 ====================
  Widget _buildRecipeTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('🍳 임박 식자재 기반 AI 저녁 추천', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                  TextButton(
                    onPressed: () {
                      setState(_syncUrgentRecipeSelection);
                      _showSnack('D-3 이내 임박 식자재만 선택했습니다.');
                    },
                    child: const Text('임박만 선택', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const Text('함께 요리할 냉장고 재료를 선택해 보세요.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              const SizedBox(height: 10),
              if (_items.isEmpty)
                const Text('등록된 식자재가 없습니다.', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _items.map((it) {
                    final sel = _selectedRecipeIds.contains(it.id);
                    final d = calcDDay(it.expiryDate);
                    return FilterChip(
                      label: Text('${it.emoji} ${it.name} (${formatDDayLabel(d)})', style: const TextStyle(fontSize: 12)),
                      selected: sel,
                      selectedColor: const Color(0xFFECFDF5),
                      checkmarkColor: const Color(0xFF059669),
                      side: BorderSide(color: d <= 3 ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0)),
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedRecipeIds.add(it.id);
                          } else {
                            _selectedRecipeIds.remove(it.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _recipeTime,
                      decoration: const InputDecoration(labelText: '조리 시간', isDense: true, border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: '15분 이내 초간단', child: Text('⚡ 15분 초간단')),
                        DropdownMenuItem(value: '25분 내외 집밥', child: Text('🍲 25분 집밥')),
                        DropdownMenuItem(value: '40분 일품요리', child: Text('👨‍🍳 40분 일품요리')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _recipeTime = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _recipeStyle,
                      decoration: const InputDecoration(labelText: '요리 스타일', isDense: true, border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: '한식 집밥', child: Text('🇰🇷 한식 집밥')),
                        DropdownMenuItem(value: '양식·파스타', child: Text('🍝 양식·파스타')),
                        DropdownMenuItem(value: '다이어트·샐러드', child: Text('🥗 가벼운 건강식')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _recipeStyle = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
                  onPressed: _isGeneratingRecipes ? null : _generateRecipes,
                  icon: _isGeneratingRecipes
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome),
                  label: Text(_isGeneratingRecipes ? 'AI가 저녁 메뉴를 구성 중...' : '선택한 식자재로 저녁 메뉴 추천받기'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ..._recipes.asMap().entries.map((entry) => _buildRecipeCard(entry.key, entry.value)),
      ],
    );
  }

  Future<void> _generateRecipes() async {
    final selectedItems = _items.where((it) => _selectedRecipeIds.contains(it.id)).toList();
    if (selectedItems.isEmpty) {
      _showSnack('레시피에 활용할 식자재를 1개 이상 선택해 주세요.');
      return;
    }

    setState(() => _isGeneratingRecipes = true);
    List<RecipeSuggestion> result = [];

    if (_apiKey.isNotEmpty) {
      try {
        result = await GeminiService.generateDinnerRecipes(
          apiKey: _apiKey,
          ingredientNames: selectedItems.map((e) => e.name).toList(),
          timePref: _recipeTime,
          stylePref: _recipeStyle,
        );
      } catch (_) {
        // fallback to offline engine below
      }
    }

    if (result.isEmpty) {
      final scored = kFallbackRecipes.map((tpl) {
        final matched = selectedItems
            .where((it) => tpl.keywords.any((kw) => it.name.contains(kw) || kw.contains(it.name.split(' ').first)))
            .toList();
        return (
          score: matched.length,
          suggestion: RecipeSuggestion(
            title: tpl.title,
            time: tpl.time,
            style: tpl.style,
            summary: tpl.summary,
            usedNames: matched.isNotEmpty ? matched.map((m) => m.name).toList() : [selectedItems.first.name],
            extraIngredients: tpl.extraIngredients,
            steps: tpl.steps,
          ),
        );
      }).toList()
        ..sort((a, b) => b.score.compareTo(a.score));

      result = scored.take(3).map((e) => e.suggestion).toList();
    }

    if (!mounted) return;
    setState(() {
      _recipes = result;
      _isGeneratingRecipes = false;
    });
  }

  Widget _buildRecipeCard(int idx, RecipeSuggestion rec) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${idx + 1}. ${rec.title}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                child: Text('⏱️ ${rec.time}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF059669))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('활용 재료: ${rec.usedNames.join(', ')}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF059669))),
          const SizedBox(height: 4),
          Text(rec.summary, style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569))),
          if (rec.extraIngredients.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10)),
              child: Text('🧂 기본 양념: ${rec.extraIngredients.join(', ')}', style: const TextStyle(fontSize: 12)),
            ),
          ],
          const SizedBox(height: 8),
          ...rec.steps.asMap().entries.map(
                (st) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('${st.key + 1}. ${st.value}', style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155))),
                ),
              ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                final usedItems = _items
                    .where((it) =>
                        _selectedRecipeIds.contains(it.id) &&
                        rec.usedNames.any((u) => it.name.contains(u) || u.contains(it.name.split(' ').first)))
                    .toList();
                final toConsume = usedItems.isNotEmpty
                    ? usedItems
                    : _items.where((it) => _selectedRecipeIds.contains(it.id)).take(1).toList();

                int addedMoney = 0;
                for (final it in toConsume) {
                  await NotificationService.instance.cancelForItem(it);
                  addedMoney += it.estimatedPrice;
                }

                setState(() {
                  final ids = toConsume.map((e) => e.id).toSet();
                  _items.removeWhere((it) => ids.contains(it.id));
                  _selectedRecipeIds.removeAll(ids);
                  _savedCount += toConsume.length;
                  _savedMoney += addedMoney;
                });
                await StorageService.saveItems(_items);
                await StorageService.saveStats(_savedCount, _savedMoney);
                _showSnack('🍳 ${rec.title} 완성! 식자재 ${toConsume.length}개 구출 (${formatWon(addedMoney)} 절약)');
              },
              icon: const Icon(Icons.check),
              label: const Text('이 메뉴로 요리 완료 (사용 식자재 소비)'),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 3. 스마트 촬영 / 등록 탭 ====================
  Widget _buildScanTab() {
    final quickIds = ['spinach', 'green_onion', 'zucchini', 'bean_sprouts', 'tofu', 'pork', 'egg', 'milk', 'cooked_rice'];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'fresh', label: Text('🥬 신선AI', style: TextStyle(fontSize: 12))),
            ButtonSegment(value: 'ocr', label: Text('🏷️ 소비기한', style: TextStyle(fontSize: 12))),
            ButtonSegment(value: 'receipt', label: Text('🧾 영수증', style: TextStyle(fontSize: 12))),
          ],
          selected: {_scanMode},
          onSelectionChanged: (s) => setState(() => _scanMode = s.first),
        ),
        const SizedBox(height: 12),

        // 카메라 미리보기 카드
        Container(
          height: 210,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_previewBytes != null)
                Image.memory(_previewBytes!, fit: BoxFit.cover)
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _scanMode == 'fresh' ? '🥬' : _scanMode == 'ocr' ? '🏷️' : '🧾',
                          style: const TextStyle(fontSize: 38),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _scanMode == 'fresh'
                              ? '채소·과일·육류를 촬영하면 오늘 날짜 기준 권장 섭취 기한과 보관법을 자동 계산합니다.'
                              : _scanMode == 'ocr'
                                  ? '포장지의 소비기한(유통기한) 날짜를 촬영하면 자동으로 날짜를 추출합니다.'
                                  : '마트 영수증을 촬영하면 비식자재를 제외하고 식자재만 한 번에 일괄 등록합니다.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_isAnalyzing)
                Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF10B981)),
                      SizedBox(height: 10),
                      Text('Gemini AI가 사진을 판독 중입니다...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _isAnalyzing ? null : () => _pickAndAnalyzeImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('카메라 촬영'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isAnalyzing ? null : () => _pickAndAnalyzeImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('앨범 선택'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _isAnalyzing ? null : _runDemoScan,
          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
          label: Text(
            _scanMode == 'receipt' ? '🧾 이마트 장보기 영수증 스캔 데모' : '✨ 촬영 없이 AI 스캔 체험 (데모)',
          ),
        ),
        const SizedBox(height: 14),

        // 등록 정보 폼 카드
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('📝 등록 정보 및 D-3 알림', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                    child: Text(_regBadge, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF059669))),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text('자주 먹는 식자재 빠른 선택', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: quickIds.map((id) {
                  final p = kFoodDatabase.firstWhere((e) => e.id == id);
                  return ActionChip(
                    label: Text('${p.emoji} ${p.name.split(' ').first}', style: const TextStyle(fontSize: 12)),
                    onPressed: () => _applyPresetToForm(p),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _regNameCtrl,
                      decoration: const InputDecoration(labelText: '품목명', isDense: true, border: OutlineInputBorder()),
                      onChanged: (val) {
                        final matched = findPresetByName(val);
                        if (matched != null && val.trim().length >= 2) {
                          setState(() {
                            _selectedPreset = matched;
                            _regEmoji = matched.emoji;
                            final days = matched.daysForZone(_regZone);
                            _regExpiryDate = addDaysStr(_regStartDate, days);
                            _regTip = matched.tipForZone(_regZone);
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _regZone,
                      decoration: const InputDecoration(labelText: '보관 구역', isDense: true, border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'fridge', child: Text('❄️ 냉장')),
                        DropdownMenuItem(value: 'freezer', child: Text('🧊 냉동')),
                        DropdownMenuItem(value: 'room', child: Text('🌡️ 실온')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _regZone = v;
                          if (_selectedPreset != null) {
                            _regExpiryDate = addDaysStr(_regStartDate, _selectedPreset!.daysForZone(v));
                            _regTip = _selectedPreset!.tipForZone(v);
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: parseDateStr(_regStartDate),
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2032),
                        );
                        if (picked != null) {
                          setState(() {
                            _regStartDate = formatDate(picked);
                            if (_selectedPreset != null) {
                              _regExpiryDate = addDaysStr(_regStartDate, _selectedPreset!.daysForZone(_regZone));
                            }
                          });
                        }
                      },
                      icon: const Icon(Icons.today, size: 16),
                      label: Text('촬영 $_regStartDate', style: const TextStyle(fontSize: 11.5)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: parseDateStr(_regExpiryDate),
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2032),
                        );
                        if (picked != null) {
                          setState(() => _regExpiryDate = formatDate(picked));
                        }
                      },
                      icon: const Icon(Icons.event_available, size: 16),
                      label: Text('만료 $_regExpiryDate', style: const TextStyle(fontSize: 11.5)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [3, 5, 7, 14, 30].map((d) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: OutlinedButton(
                        onPressed: () => setState(() => _regExpiryDate = addDaysStr(_regStartDate, d)),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
                        child: Text('+$d일', style: const TextStyle(fontSize: 11)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _regMemoCtrl,
                decoration: const InputDecoration(
                  labelText: '수량 / 메모 (선택)',
                  hintText: '예: 1봉지, 손질 완료',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Text('💡 보관 가이드: $_regTip', style: const TextStyle(fontSize: 12.5, color: Color(0xFF065F46))),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _regZone == 'freezer' ? '🔔 폐기 7일 전(D-7) 네이티브 알람 예약' : '🔔 폐기 3일 전(D-3) 네이티브 알람 예약',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                value: _regReminder,
                onChanged: (v) => setState(() => _regReminder = v),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saveNewItem,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('냉장고에 등록 및 D-3 알람 예약'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _applyPresetToForm(FoodPreset preset) {
    final zone = preset.defaultZone;
    final days = preset.daysForZone(zone);
    setState(() {
      _selectedPreset = preset;
      _regNameCtrl.text = preset.name;
      _regEmoji = preset.emoji;
      _regZone = zone;
      _regExpiryDate = addDaysStr(_regStartDate, days);
      _regTip = preset.tipForZone(zone);
      _regBadge = '표준 기준 ($days일)';
    });
  }

  Future<void> _pickAndAnalyzeImage(ImageSource source) async {
    final XFile? file = await _picker.pickImage(source: source, maxWidth: 1024, imageQuality: 82);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    setState(() => _previewBytes = bytes);

    if (_apiKey.isEmpty) {
      _showSnack('알림·설정 탭에서 Gemini API 키를 입력하면 실제 사진이 분석됩니다. 데모 결과를 표시합니다.');
      _runDemoScan();
      return;
    }

    setState(() => _isAnalyzing = true);
    try {
      final b64 = base64Encode(bytes);
      final today = todayDateStr();

      if (_scanMode == 'receipt') {
        final draftItems = await GeminiService.scanReceiptBatch(_apiKey, b64);
        if (!mounted) return;
        if (draftItems.isEmpty) {
          _showSnack('영수증에서 식자재를 인식하지 못했습니다. 선명하게 다시 촬영해 주세요.');
        } else {
          _openBatchReviewSheet(draftItems);
        }
      } else if (_scanMode == 'ocr') {
        final res = await GeminiService.scanExpiryOcr(_apiKey, b64);
        if (!mounted) return;
        setState(() {
          _regNameCtrl.text = res['name']?.toString() ?? '가공식품';
          _regEmoji = res['emoji']?.toString() ?? '📦';
          _regZone = res['zone']?.toString() ?? 'fridge';
          _regStartDate = today;
          _regExpiryDate = res['expiryDate']?.toString() ?? addDaysStr(today, 7);
          _regTip = res['tip']?.toString() ?? '표기된 소비기한 내 냉장 보관하세요.';
          _regMemoCtrl.text = '소비기한 OCR 스캔';
          _regBadge = '🏷️ OCR 인식 완료';
        });
        _showSnack('소비기한(${_regExpiryDate}) OCR 스캔이 완료되었습니다!');
      } else {
        final res = await GeminiService.analyzeFreshFood(_apiKey, b64);
        if (!mounted) return;
        final days = (res['recommendedDays'] as num?)?.toInt() ?? 5;
        setState(() {
          _regNameCtrl.text = res['name']?.toString() ?? '신선 식자재';
          _regEmoji = res['emoji']?.toString() ?? '🥬';
          _regZone = res['zone']?.toString() ?? 'fridge';
          _regStartDate = today;
          _regExpiryDate = addDaysStr(today, days.clamp(1, 180));
          _regTip = res['tip']?.toString() ?? '밀폐 보관해 신선도를 유지하세요.';
          _regMemoCtrl.text = res['memo']?.toString() ?? 'AI 분석 ($days일 권장)';
          _regBadge = '✨ AI 분석 완료';
        });
        _showSnack('${_regNameCtrl.text} 인식 완료! 오늘 기준 $days일 내 섭취 권장');
      }
    } catch (e) {
      _showSnack('AI 분석 중 오류가 발생했습니다. API 키와 인터넷 연결을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _runDemoScan() {
    final today = todayDateStr();
    if (_scanMode == 'receipt') {
      _openBatchReviewSheet([
        BatchDraftItem(name: '애호박', emoji: '🥒', zone: 'fridge', expiryDate: addDaysStr(today, 6), tip: '물기를 닦아 키친타월로 감싸 꼭지가 위로 가게 세워 보관하세요.', estimatedPrice: 2500),
        BatchDraftItem(name: '콩나물', emoji: '🌱', zone: 'fridge', expiryDate: addDaysStr(today, 3), tip: '밀폐용기에 찬물을 부어 잠기게 보관하세요.', estimatedPrice: 2000),
        BatchDraftItem(name: '닭가슴살 (생닭)', emoji: '🍗', zone: 'fridge', expiryDate: addDaysStr(today, 2), tip: '부패가 빠르므로 2일 내 조리하거나 소분 냉동하세요.', estimatedPrice: 7500),
        BatchDraftItem(name: '파프리카', emoji: '🫑', zone: 'fridge', expiryDate: addDaysStr(today, 8), tip: '물기를 닦아 개별 랩 포장 후 지퍼백에 보관하세요.', estimatedPrice: 3500),
        BatchDraftItem(name: '식빵 · 베이글', emoji: '🍞', zone: 'freezer', expiryDate: addDaysStr(today, 25), tip: '1~2조각씩 랩으로 싸서 냉동 후 토스터에 바로 구워 드세요.', estimatedPrice: 4000),
      ]);
      return;
    }

    if (_scanMode == 'ocr') {
      setState(() {
        _regNameCtrl.text = '국산콩 부침두부 300g';
        _regEmoji = '🧊';
        _regZone = 'fridge';
        _regStartDate = today;
        _regExpiryDate = addDaysStr(today, 4);
        _regTip = '개봉 후 남은 두부는 밀폐용기에 잠길 만큼 생수를 붓고 소금 한 꼬집을 넣어 냉장 보관하세요.';
        _regMemoCtrl.text = '소비기한 OCR 데모';
        _regBadge = '🏷️ OCR 데모';
      });
      _showSnack('기성품 소비기한 OCR 스캔 데모가 적용되었습니다.');
      return;
    }

    setState(() {
      _regNameCtrl.text = '애호박';
      _regEmoji = '🥒';
      _regZone = 'fridge';
      _regStartDate = today;
      _regExpiryDate = addDaysStr(today, 6);
      _regTip = '표면 물기를 닦아 하나씩 키친타월이나 신문지로 감싼 뒤 꼭지가 위로 가도록 세워서 냉장 보관하세요.';
      _regMemoCtrl.text = '통채소 AI 인식 데모';
      _regBadge = '✨ 신선식품 AI 데모';
    });
    _showSnack('애호박 인식 완료! 오늘 기준 6일 이내 섭취 권장');
  }

  void _openBatchReviewSheet(List<BatchDraftItem> drafts) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            return SizedBox(
              height: MediaQuery.of(sheetCtx).size.height * 0.78,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🧾 영수증 식자재 일괄 검수', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const Text('비식자재를 제외하고 인식된 식자재입니다. 구역·만료일을 조정하세요.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: drafts.length,
                        itemBuilder: (_, idx) {
                          final it = drafts[idx];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Checkbox(
                                      value: it.checked,
                                      onChanged: (v) => setSheetState(() => it.checked = v ?? true),
                                    ),
                                    Text(it.emoji, style: const TextStyle(fontSize: 18)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(it.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: it.zone,
                                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                        items: const [
                                          DropdownMenuItem(value: 'fridge', child: Text('❄️ 냉장실')),
                                          DropdownMenuItem(value: 'freezer', child: Text('🧊 냉동실')),
                                          DropdownMenuItem(value: 'room', child: Text('🌡️ 실온')),
                                        ],
                                        onChanged: (newZone) {
                                          if (newZone == null) return;
                                          final preset = findPresetByName(it.name);
                                          final today = todayDateStr();
                                          setSheetState(() {
                                            it.zone = newZone;
                                            if (preset != null) {
                                              it.expiryDate = addDaysStr(today, preset.daysForZone(newZone));
                                              it.tip = preset.tipForZone(newZone);
                                            } else {
                                              it.expiryDate = addDaysStr(today, newZone == 'freezer' ? 30 : 5);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: () async {
                                        final picked = await showDatePicker(
                                          context: sheetCtx,
                                          initialDate: parseDateStr(it.expiryDate),
                                          firstDate: DateTime(2024),
                                          lastDate: DateTime(2032),
                                        );
                                        if (picked != null) {
                                          setSheetState(() => it.expiryDate = formatDate(picked));
                                        }
                                      },
                                      child: Text(it.expiryDate, style: const TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final selected = drafts.where((d) => d.checked).toList();
                          if (selected.isEmpty) return;
                          final today = todayDateStr();
                          final nowMs = DateTime.now().millisecondsSinceEpoch;
                          final newList = <FoodItem>[];
                          for (int i = 0; i < selected.length; i++) {
                            final d = selected[i];
                            final food = FoodItem(
                              id: 'batch-$nowMs-$i',
                              name: d.name,
                              emoji: d.emoji,
                              category: '영수증등록',
                              zone: d.zone,
                              registeredDate: today,
                              expiryDate: d.expiryDate,
                              sourceType: 'receipt',
                              tip: d.tip,
                              reminderEnabled: true,
                              reminderOffset: d.zone == 'freezer' ? 7 : 3,
                              estimatedPrice: d.estimatedPrice,
                              memo: '영수증 일괄 스캔',
                            );
                            newList.add(food);
                            await NotificationService.instance.scheduleForItem(food, _notifyHour, _notifyMinute);
                          }
                          setState(() {
                            _items = [...newList, ..._items];
                            _tabIndex = 0;
                          });
                          await StorageService.saveItems(_items);
                          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                          _showSnack('영수증 식자재 ${newList.length}개 등록 및 D-3 네이티브 알람 예약 완료!');
                        },
                        icon: const Icon(Icons.check),
                        label: Text('선택 품목 (${drafts.where((d) => d.checked).length}개) 일괄 등록'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveNewItem() async {
    final name = _regNameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('식자재 품목명을 입력해 주세요.');
      return;
    }

    final preset = findPresetByName(name);
    final offset = _regZone == 'freezer' ? 7 : 3;
    final newItem = FoodItem(
      id: 'item-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      emoji: _regEmoji,
      category: preset?.category ?? '일반식자재',
      zone: _regZone,
      registeredDate: _regStartDate,
      expiryDate: _regExpiryDate,
      sourceType: _scanMode,
      tip: _regTip,
      reminderEnabled: _regReminder,
      reminderOffset: offset,
      estimatedPrice: preset?.estimatedPrice ?? 3500,
      memo: _regMemoCtrl.text.trim(),
    );

    setState(() {
      _items.insert(0, newItem);
      _regNameCtrl.clear();
      _regMemoCtrl.clear();
      _selectedPreset = null;
      _previewBytes = null;
      _tabIndex = 0;
    });

    await StorageService.saveItems(_items);
    await NotificationService.instance.scheduleForItem(newItem, _notifyHour, _notifyMinute);

    final dDay = calcDDay(newItem.expiryDate);
    _showSnack('${newItem.name} 등록 완료! (${formatDDayLabel(dDay)}, D-$offset 알람 예약)');
  }

  // ==================== 4. 보관 가이드 & 절약 리포트 탭 ====================
  Widget _buildGuideTab() {
    final list = kFoodDatabase.where((p) {
      if (_guideSearch.isEmpty) return true;
      final q = _guideSearch.toLowerCase();
      return p.name.toLowerCase().contains(q) || p.category.toLowerCase().contains(q);
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFA7F3D0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🌱 내 냉장고 식비 절약 리포트', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF065F46))),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          Text('$_savedCount개', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF059669))),
                          const Text('기한 내 구출 식자재', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        children: [
                          Text(formatWon(_savedMoney), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF059669))),
                          const Text('예상 식비 절약', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            hintText: '보관법 백과 검색 (예: 대파, 삼겹살, 두부, 식빵)',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: (v) => setState(() => _guideSearch = v),
        ),
        const SizedBox(height: 12),
        ...list.map((p) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${p.emoji} ${p.name}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    Text(p.category, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    Chip(label: Text('❄️ 냉장 ${p.fridgeDays}일', style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
                    Chip(label: Text('🧊 냉동 ${p.freezerDays}일', style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
                    if (p.roomDays > 0)
                      Chip(label: Text('🌡️ 실온 ${p.roomDays}일', style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
                  ],
                ),
                const SizedBox(height: 4),
                Text('• 냉장 보관: ${p.fridgeTip}', style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155))),
                const SizedBox(height: 4),
                Text('• 냉동·해동: ${p.freezerTip}', style: const TextStyle(fontSize: 12.5, color: Color(0xFF0369A1))),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ==================== 5. 네이티브 D-3 알람 & 설정 탭 ====================
  Widget _buildSettingsTab() {
    final activeAlarms = _items.where((it) => it.reminderEnabled).toList()
      ..sort((a, b) => calcDDay(a.expiryDate).compareTo(calcDDay(b.expiryDate)));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // 네이티브 알람 설정 카드
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🔔 Android 백그라운드 D-3 네이티브 알람', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                '앱을 완전히 종료해 두어도 섭취 만료 3일 전(냉동은 7일 전) 지정 시각에 스마트폰 상단 푸시 알람이 울립니다.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(hour: _notifyHour, minute: _notifyMinute),
                        );
                        if (picked != null) {
                          setState(() {
                            _notifyHour = picked.hour;
                            _notifyMinute = picked.minute;
                          });
                          await StorageService.saveNotifyTime(_notifyHour, _notifyMinute);
                          await NotificationService.instance.rescheduleAll(_items, _notifyHour, _notifyMinute);
                          _showSnack('알림 시각이 $_formattedNotifyTime으로 변경되어 전체 재예약되었습니다.');
                        }
                      },
                      icon: const Icon(Icons.access_time),
                      label: Text('알람 시각 $_formattedNotifyTime'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        await NotificationService.instance.requestPermission();
                        await NotificationService.instance.showImmediateTest(_items);
                        _showSnack('즉시 테스트 푸시 알림을 발송했습니다!');
                      },
                      icon: const Icon(Icons.notifications_active),
                      label: const Text('즉시 알림 테스트'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await NotificationService.instance.requestPermission();
                    await NotificationService.instance.schedule10SecondBackgroundTest();
                    _showSnack('10초 뒤 백그라운드 알람이 예약되었습니다! 앱을 닫아 보세요.');
                  },
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('⏱️ 10초 뒤 백그라운드 알람 테스트 (앱 종료 상태 확인)'),
                ),
              ),
              const SizedBox(height: 12),
              const Text('예약된 알람 목록', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
              const SizedBox(height: 6),
              if (activeAlarms.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('예약된 알람이 없습니다.', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                )
              else
                ...activeAlarms.map((it) {
                  final notifyDate = addDaysStr(it.expiryDate, -it.reminderOffset);
                  final d = calcDDay(it.expiryDate);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: d <= it.reminderOffset ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Text(it.emoji, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${it.name} (${formatDDayLabel(d)})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                              Text('알람 예약: $notifyDate $_formattedNotifyTime (만료 ${it.reminderOffset}일 전)',
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Gemini AI API 키 설정 카드
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🤖 Gemini Vision AI 카메라 인식 연동', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                'Google AI Studio(aistudio.google.com)에서 무료 발급받은 Gemini API 키를 입력하면 실제 채소 촬영·소비기한 OCR·영수증 일괄 스캔이 100% 실시간으로 동작합니다. 키는 스마트폰 내부에만 저장됩니다.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _apiKeyCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: 'AIzaSy... 형태의 Gemini API 키 입력',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final k = _apiKeyCtrl.text.trim();
                        await StorageService.saveApiKey(k);
                        setState(() => _apiKey = k);
                        _showSnack(k.isNotEmpty ? 'Gemini API 키가 안전하게 저장되었습니다!' : 'API 키가 비워졌습니다.');
                      },
                      child: const Text('💾 API 키 저장'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      _apiKeyCtrl.clear();
                      await StorageService.saveApiKey('');
                      setState(() => _apiKey = '');
                      _showSnack('API 키가 초기화되었습니다.');
                    },
                    child: const Text('초기화'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 샘플 초기화
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB91C1C)),
          onPressed: () async {
            final sample = buildInitialSampleItems();
            setState(() {
              _items = sample;
              _syncUrgentRecipeSelection();
            });
            await StorageService.saveItems(_items);
            await NotificationService.instance.rescheduleAll(_items, _notifyHour, _notifyMinute);
            _showSnack('오늘 날짜 기준 샘플 데이터로 초기화되었습니다.');
          },
          icon: const Icon(Icons.refresh),
          label: const Text('샘플 식자재 데이터로 초기화'),
        ),
      ],
    );
  }
}
