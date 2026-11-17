import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TodaysRecipeApp());
}

class TodaysRecipeApp extends StatelessWidget {
  const TodaysRecipeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '오늘의 요리',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE86F3A),
          surface: const Color(0xFFFFFBF7),
        ),
        scaffoldBackgroundColor: const Color(0xFFFFFBF7),
        fontFamily: 'sans-serif',
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const String _dataUrl =
      'https://cdn.jsdelivr.net/gh/hyuckiii-real/todays-recipe-data@main/today.json';
  static const String _fallbackUrl =
      'https://raw.githubusercontent.com/hyuckiii-real/todays-recipe-data/main/today.json';

  int _selectedIndex = 0;
  Map<String, dynamic>? _recipe;
  bool _isLoading = true;
  String? _errorMessage;

  // 장보기 체크 상태 & 대체 재료 펼침 상태
  final Set<int> _checkedIngredients = {};
  final Set<int> _expandedSubstitutes = {};

  // 식탁 일기 (완료 히스토리)
  var _diaryList = >[];

  // AdMob 배너
  BannerAd? _bannerAd;
  bool _isBannerReady = false;

  @override
  void initState() {
    super.initState();
    _loadCachedAndFetch();
    _initAdMobInBackground();
  }

  Future<void> _initAdMobInBackground() async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      await MobileAds.instance.initialize();
      if (!mounted) return;
      final banner = BannerAd(
        adUnitId: 'ca-app-pub-3940256099942544/6300978111',
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (mounted) {
              setState(() {
                _bannerAd = ad as BannerAd;
                _isBannerReady = true;
              });
            }
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
          },
        ),
      );
      await banner.load();
    } catch (_) {}
  }

  Future<void> _loadCachedAndFetch() async {
    final prefs = await SharedPreferences.getInstance();

    // 일기 목록 복원
    final diaryRaw = prefs.getString('recipe_diary_list');
    if (diaryRaw != null) {
      try {
        final decoded = jsonDecode(diaryRaw) as List;
        _diaryList = decoded.cast>();
      } catch (_) {}
    }

    // 캐시된 레시피 즉시 표시
    final cachedRecipeRaw = prefs.getString('cached_today_recipe');
    if (cachedRecipeRaw != null) {
      try {
        final decoded = jsonDecode(cachedRecipeRaw) as Map<String, dynamic>;
        final savedChecked =
            prefs.getStringList('checked_${decoded['date']}') ?? [];
        if (mounted) {
          setState(() {
            _recipe = decoded;
            _checkedIngredients
              ..clear()
              ..addAll(savedChecked.map(int.parse));
            _isLoading = false;
          });
        }
      } catch (_) {}
    }

    // 최신 데이터 네트워크 조회
    try {
      http.Response res = await http
          .get(Uri.parse('$_dataUrl?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        res = await http
            .get(Uri.parse(_fallbackUrl))
            .timeout(const Duration(seconds: 8));
      }
      if (res.statusCode == 200) {
        final decoded =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        await prefs.setString('cached_today_recipe', jsonEncode(decoded));
        final savedChecked =
            prefs.getStringList('checked_${decoded['date']}') ?? [];
        if (mounted) {
          setState(() {
            _recipe = decoded;
            _checkedIngredients
              ..clear()
              ..addAll(savedChecked.map(int.parse));
            _isLoading = false;
            _errorMessage = null;
          });
        }
      } else if (_recipe == null && mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '오늘의 요리를 불러오지 못했어요. (${res.statusCode})';
        });
      }
    } catch (e) {
      if (_recipe == null && mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '인터넷 연결을 확인한 뒤 다시 시도해 주세요.';
        });
      }
    }
  }

  Future<void> _toggleIngredient(int index) async {
    setState(() {
      if (_checkedIngredients.contains(index)) {
        _checkedIngredients.remove(index);
      } else {
        _checkedIngredients.add(index);
      }
    });
    if (_recipe != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'checked_${_recipe!['date']}',
        _checkedIngredients.map((e) => e.toString()).toList(),
      );
    }
  }

  Future<void> _completeTodayCooking(String note, String ratingEmoji) async {
    if (_recipe == null) return;
    final prefs = await SharedPreferences.getInstance();
    final entry = {
      'date': _recipe!['date'] ?? '',
      'menu_name': _recipe!['menu_name'] ?? '',
      'emoji': _recipe!['emoji'] ?? '🍳',
      'rating': ratingEmoji,
      'note': note.trim().isEmpty ? '오늘도 직접 해먹기 성공!' : note.trim(),
    };
    setState(() {
      _diaryList.removeWhere((item) => item['date'] == entry['date']);
      _diaryList.insert(0, entry);
      _selectedIndex = 3;
    });
    await prefs.setString('recipe_diary_list', jsonEncode(_diaryList));
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7),
        elevation: 0,
        title: Row(
          children: [
            const Text('🍳 ', style: TextStyle(fontSize: 22)),
            const Text(
              '오늘의 요리',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: Color(0xFF2D241E),
              ),
            ),
            const Spacer(),
            if (_recipe != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEFE6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _recipe!['date'] ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFD95B26),
                  ),
                ),
              ),
          ],
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isBannerReady && _bannerAd != null)
            SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
          NavigationBar(
            selectedIndex: _selectedIndex,
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xFFFFE5D6),
            onDestinationSelected: (idx) =>
                setState(() => _selectedIndex = idx),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.restaurant_menu_outlined),
                selectedIcon:
                    Icon(Icons.restaurant_menu, color: Color(0xFFE86F3A)),
                label: '오늘의 요리',
              ),
              NavigationDestination(
                icon: Icon(Icons.shopping_basket_outlined),
                selectedIcon:
                    Icon(Icons.shopping_basket, color: Color(0xFFE86F3A)),
                label: '10분 장보기',
              ),
              NavigationDestination(
                icon: Icon(Icons.timer_outlined),
                selectedIcon: Icon(Icons.timer, color: Color(0xFFE86F3A)),
                label: '요리 모드',
              ),
              NavigationDestination(
                icon: Icon(Icons.book_outlined),
                selectedIcon: Icon(Icons.book, color: Color(0xFFE86F3A)),
                label: '식탁 일기',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🍳', style: TextStyle(fontSize: 48)),
            SizedBox(height: 16),
            Text(
              '오늘 따라 해볼 만한 요리를 고르고 있어요...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    if (_errorMessage != null || _recipe == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage ?? '데이터가 없습니다.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() => _isLoading = true);
                  _loadCachedAndFetch();
                },
                child: const Text('다시 불러오기'),
              ),
            ],
          ),
        ),
      );
    }

    switch (_selectedIndex) {
      case 0:
        return _buildOverviewTab();
      case 1:
        return _buildShoppingTab();
      case 2:
        return _buildCookingTab();
      case 3:
        return _buildDiaryTab();
      default:
        return _buildOverviewTab();
    }
  }

  // 1번 탭: 오늘의 요리 소개
  Widget _buildOverviewTab() {
    final r = _recipe!;
    final isAlreadyDone = _diaryList.any((item) => item['date'] == r['date']);
    final ingredientsList = (r['ingredients'] as List?) ?? [];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.brown.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEFE6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    r['theme_badge'] ?? '오늘의 추천',
                    style: const TextStyle(
                      color: Color(0xFFD95B26),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(r['emoji'] ?? '🍳',
                        style: const TextStyle(fontSize: 44)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        r['menu_name'] ?? '',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF2D241E),
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _infoChip(Icons.schedule, '약 ${r['cook_time_minutes']}분'),
                    const SizedBox(width: 10),
                    _infoChip(
                        Icons.thumb_up_alt_outlined, r['difficulty'] ?? '쉬움'),
                    const SizedBox(width: 10),
                    _infoChip(Icons.kitchen_outlined,
                        '재료 ${ingredientsList.length}가지'),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7F0),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFDFC9)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💬 ', style: TextStyle(fontSize: 18)),
                      Expanded(
                        child: Text(
                          r['friend_message'] ?? '',
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: Color(0xFF4A3B32),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF2D241E),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🔥 오늘의 요리 미션',
                        style: TextStyle(
                            color: Color(0xFFFFB284),
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    const Spacer(),
                    if (isAlreadyDone)
                      const Text('✅ 완료함',
                          style: TextStyle(
                              color: Color(0xFF8CE99A),
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  r['today_mission'] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE86F3A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => setState(() => _selectedIndex = 1),
              icon: const Icon(Icons.shopping_basket),
              label: const Text(
                '10분 장보기 체크하러 가기',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F1EC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF6E5D52)),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A3B32),
            ),
          ),
        ],
      ),
    );
  }

  // 2번 탭: 10분 장보기 & 대체 재료
  Widget _buildShoppingTab() {
    final ingredients =
        (_recipe!['ingredients'] as List).cast>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '10분 장보기 체크리스트',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            '집에 있는 건 체크하고, 없는 건 "없다면?"을 눌러 대체 재료를 확인하세요.',
            style: TextStyle(fontSize: 14, color: Color(0xFF6E5D52)),
          ),
          const SizedBox(height: 18),
          ...List.generate(ingredients.length, (i) {
            final item = ingredients[i];
            final checked = _checkedIngredients.contains(i);
            final showSub = _expandedSubstitutes.contains(i);
            final isBuy = item['category'] == '장보기 재료';
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: checked ? const Color(0xFFF4EFEA) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: checked
                      ? const Color(0xFFDCD3CA)
                      : const Color(0xFFF0E6DD),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: checked,
                        activeColor: const Color(0xFFE86F3A),
                        onChanged: (_) => _toggleIngredient(i),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _toggleIngredient(i),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item['category'] ?? '',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isBuy
                                      ? const Color(0xFFD95B26)
                                      : const Color(0xFF2B8A3E),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item['name'] ?? '',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  decoration: checked
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: checked
                                      ? Colors.grey
                                      : const Color(0xFF2D241E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (showSub) {
                              _expandedSubstitutes.remove(i);
                            } else {
                              _expandedSubstitutes.add(i);
                            }
                          });
                        },
                        child: Text(
                          showSub ? '닫기' : '없다면?',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE86F3A),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (showSub)
                    Container(
                      width: double.infinity,
                      margin:
                          const EdgeInsets.only(top: 8, left: 12, right: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7F0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '💡 ${item['substitute'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF4A3B32),
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE86F3A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => setState(() => _selectedIndex = 2),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text(
                '재료 준비 끝! 요리 시작하기',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 3번 탭: 큰 글씨 요리 모드 + 내장 타이머 + 완료 인증
  Widget _buildCookingTab() {
    final steps = (_recipe!['steps'] as List).cast>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_recipe!['emoji'] ?? '🍳'} ${_recipe!['menu_name'] ?? ''}',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            '단계별로 천천히 따라 해보세요. 불 앞에서는 아래 타이머를 바로 켜세요!',
            style: TextStyle(fontSize: 14, color: Color(0xFF6E5D52)),
          ),
          const SizedBox(height: 18),
          ...steps.map((step) => _StepCardWidget(step: step)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2B8A3E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _showCompleteDialog,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text(
                '요리 완성! 식탁 일기에 기록하기',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCompleteDialog() {
    final controller = TextEditingController();
    String selectedRating = '😋 최고예요';
    final ratings = ['😋 최고예요', '👍 괜찮아요', '😅 다음엔 더 잘할래요'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('오늘의 요리 완성 축하해요! 🎉',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('맛은 어땠나요?', style: TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: ratings.map((r) {
                  final selected = selectedRating == r;
                  return ChoiceChip(
                    label: Text(r, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (_) =>
                        setDialogState(() => selectedRating = r),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: '한 줄 소감 (예: 대파 듬뿍 넣으니 진짜 맛있음!)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _completeTodayCooking(controller.text, selectedRating);
              },
              child: const Text('일기 저장'),
            ),
          ],
        ),
      ),
    );
  }

  // 4번 탭: 나만의 식탁 일기
  Widget _buildDiaryTab() {
    if (_diaryList.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('🍽️', style: TextStyle(fontSize: 48)),
              SizedBox(height: 14),
              Text(
                '아직 기록된 요리가 없어요',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                '오늘의 요리를 직접 만들어 보고\n[요리 완성!] 버튼을 눌러 첫 기록을 남겨보세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF6E5D52), height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _diaryList.length,
      itemBuilder: (context, idx) {
        final item = _diaryList[idx];
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFF0E6DD)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(item['emoji'] ?? '🍳',
                      style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['menu_name'] ?? '',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          item['date'] ?? '',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF8C7A6B)),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEFE6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      item['rating'] ?? '',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item['note'] ?? '',
                style: const TextStyle(
                    fontSize: 14.5, color: Color(0xFF4A3B32), height: 1.4),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StepCardWidget extends StatefulWidget {
  final Map<String, dynamic> step;
  const _StepCardWidget({required this.step});

  @override
  State<_StepCardWidget> createState() => _StepCardWidgetState();
}

class _StepCardWidgetState extends State<_StepCardWidget> {
  Timer? _timer;
  late int _remainingSeconds;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = (widget.step['timer_seconds'] as int?) ?? 0;
  }

  void _toggleTimer() {
    if (_isRunning) {
      _timer?.cancel();
      setState(() => _isRunning = false);
    } else {
      if (_remainingSeconds <= 0) {
        _remainingSeconds = (widget.step['timer_seconds'] as int?) ?? 0;
      }
      setState(() => _isRunning = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_remainingSeconds <= 1) {
          t.cancel();
          if (mounted) {
            setState(() {
              _remainingSeconds = 0;
              _isRunning = false;
            });
          }
        } else if (mounted) {
          setState(() => _remainingSeconds--);
        }
      });
    }
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _remainingSeconds = (widget.step['timer_seconds'] as int?) ?? 0;
    });
  }

  String _formatTime(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialSec = (widget.step['timer_seconds'] as int?) ?? 0;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0E6DD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFFE86F3A),
                child: Text(
                  '${widget.step['step_number']}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.step['title'] ?? '',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.step['instruction'] ?? '',
            style: const TextStyle(
              fontSize: 17,
              height: 1.55,
              color: Color(0xFF2D241E),
            ),
          ),
          if (initialSec > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _remainingSeconds == 0
                    ? const Color(0xFFEBFBEE)
                    : const Color(0xFFFFF7F0),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer, color: Color(0xFFE86F3A)),
                  const SizedBox(width: 8),
                  Text(
                    _remainingSeconds == 0
                        ? '타이머 완료!'
                        : _formatTime(_remainingSeconds),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFD95B26),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.tonal(
                    onPressed: _toggleTimer,
                    child: Text(_isRunning ? '일시정지' : '시작'),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: _resetTimer,
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
