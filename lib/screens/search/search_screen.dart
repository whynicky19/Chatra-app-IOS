import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../providers/classes_provider.dart';
import '../../providers/chats_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../classes/class_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String _query = '';
  List<String> _recent = [];
  List<dynamic> _classes = [];
  List<dynamic> _assignments = [];
  List<dynamic> _chats = [];
  bool _hasResults = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
    _loadRecent();
    _loadData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final uid = context.read<AuthProvider>().userId ?? 0;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _recent = prefs.getStringList('recent_searches_$uid') ?? [];
    });
  }

  Future<void> _saveQuery(String q) async {
    if (q.trim().isEmpty) return;
    final uid = context.read<AuthProvider>().userId ?? 0;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('recent_searches_$uid') ?? [];
    list.remove(q);
    list.insert(0, q);
    if (list.length > 5) list.removeLast();
    await prefs.setStringList('recent_searches_$uid', list);
    if (!mounted) return;
    setState(() => _recent = list);
  }

  Future<void> _loadData() async {
    final cp = context.read<ClassesProvider>();
    _classes = cp.allClasses;
    try {
      final api = context.read<ApiService>();
      _assignments = await api.getAssignments();
      if (!mounted) return;
    } catch (_) {}
    _chats = context.read<ChatsProvider>().chats;
  }

  void _onChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _query = val.trim();
        _hasResults = _query.isNotEmpty && (
          _filterClasses().isNotEmpty ||
          _filterAssignments().isNotEmpty ||
          _filterChats().isNotEmpty
        );
      });
      if (_hasResults) _saveQuery(_query);
    });
  }

  List<dynamic> _filterClasses() {
    if (_query.isEmpty) return [];
    final q = _query.toLowerCase();
    return _classes.where((c) =>
      (c['title'] ?? '').toString().toLowerCase().contains(q) ||
      (c['teacher_name'] ?? '').toString().toLowerCase().contains(q)
    ).toList();
  }

  List<dynamic> _filterAssignments() {
    if (_query.isEmpty) return [];
    final q = _query.toLowerCase();
    return _assignments.where((a) =>
      (a['title'] ?? '').toString().toLowerCase().contains(q)
    ).toList();
  }

  List<dynamic> _filterChats() {
    if (_query.isEmpty) return [];
    final q = _query.toLowerCase();
    final cp = context.read<ChatsProvider>();
    return _chats.where((c) =>
      cp.chatTitle(c).toLowerCase().contains(q)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(child: Column(children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: adaptiveSurface2(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back_ios_new, size: 16, color: C.teal),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(
              decoration: BoxDecoration(
                color: adaptiveSurface2(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l.t('search_hint'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: C.text4),
                  suffixIcon: _ctrl.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _ctrl.clear();
                            setState(() { _query = ''; _hasResults = false; });
                          },
                          child: const Icon(Icons.close, size: 18, color: C.text4),
                        )
                      : null,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: _onChanged,
              ),
            )),
          ]),
        ),

        // Body
        Expanded(child: _query.isEmpty ? _buildRecent(l) : _buildResults(l, isDark)),
      ])),
    );
  }

  Widget _buildRecent(L10n l) {
    if (_recent.isEmpty) return const SizedBox();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      children: [
        Text(l.t('recent_searches'), style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
          color: C.text4, letterSpacing: 1,
        )),
        const SizedBox(height: 10),
        ..._recent.map((q) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.history, color: C.text4, size: 20),
          title: Text(q, style: const TextStyle(fontSize: 14)),
          onTap: () {
            _ctrl.text = q;
            _ctrl.selection = TextSelection.fromPosition(TextPosition(offset: q.length));
            _onChanged(q);
          },
        )),
      ],
    );
  }

  Widget _buildResults(L10n l, bool isDark) {
    final classes = _filterClasses();
    final assignments = _filterAssignments();
    final chats = _filterChats();
    final any = classes.isNotEmpty || assignments.isNotEmpty || chats.isNotEmpty;

    if (!any) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.search_off_rounded, size: 52, color: C.text4),
        const SizedBox(height: 12),
        Text('${l.t('search_empty')} «$_query»',
          style: const TextStyle(fontSize: 14, color: C.text4),
          textAlign: TextAlign.center,
        ),
      ]));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
      children: [
        if (classes.isNotEmpty) ...[
          _sectionHeader(l.t('section_classes')),
          ..._buildClassItems(classes.take(3).toList(), isDark),
          if (classes.length > 3) _moreBtn('${l.t('show_more')} ${classes.length - 3}', () {}),
        ],
        if (assignments.isNotEmpty) ...[
          _sectionHeader(l.t('section_assignments')),
          ..._buildAssignmentItems(assignments.take(3).toList(), isDark),
          if (assignments.length > 3) _moreBtn('${l.t('show_more')} ${assignments.length - 3}', () {}),
        ],
        if (chats.isNotEmpty) ...[
          _sectionHeader(l.t('section_chats')),
          ..._buildChatItems(chats.take(3).toList(), isDark),
          if (chats.length > 3) _moreBtn('${l.t('show_more')} ${chats.length - 3}', () {}),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(title, style: const TextStyle(
      fontSize: 11, fontWeight: FontWeight.w800,
      color: C.text4, letterSpacing: 1.2,
    )),
  );

  Widget _moreBtn(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(label, style: const TextStyle(fontSize: 13, color: C.teal, fontWeight: FontWeight.w600)),
    ),
  );

  List<Widget> _buildClassItems(List<dynamic> items, bool isDark) => items.map((c) {
    final id = (c['id'] as num?)?.toInt() ?? 0;
    return _ResultTile(
      icon: Icons.menu_book_rounded,
      title: c['title'] ?? '',
      subtitle: c['teacher_name'] ?? '',
      query: _query,
      isDark: isDark,
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => ClassDetailScreen(classId: id),
      )),
    );
  }).toList();

  List<Widget> _buildAssignmentItems(List<dynamic> items, bool isDark) => items.map((a) {
    final classId = (a['class_id'] as num?)?.toInt() ?? 0;
    return _ResultTile(
      icon: Icons.assignment_rounded,
      title: a['title'] ?? '',
      subtitle: a['due_date'] ?? '',
      query: _query,
      isDark: isDark,
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => ClassDetailScreen(classId: classId, initialTab: 2),
      )),
    );
  }).toList();

  List<Widget> _buildChatItems(List<dynamic> items, bool isDark) {
    final cp = context.read<ChatsProvider>();
    return items.map((c) {
      final id = (c['id'] as num?)?.toInt() ?? 0;
      return _ResultTile(
        icon: Icons.chat_bubble_outline_rounded,
        title: cp.chatTitle(c),
        subtitle: '',
        query: _query,
        isDark: isDark,
        onTap: () {
          Navigator.pop(context);
          cp.setActiveChatId(id);
        },
      );
    }).toList();
  }
}

class _ResultTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String query;
  final bool isDark;
  final VoidCallback onTap;

  const _ResultTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.query,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: softShadow(isDark),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: C.teal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: C.teal),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _highlighted(title, query),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: const TextStyle(fontSize: 12, color: C.text4), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          const Icon(Icons.chevron_right, size: 16, color: C.text4),
        ]),
      ),
    );
  }

  Widget _highlighted(String text, String query) {
    if (query.isEmpty) {
      return Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final idx = lower.indexOf(q);
    if (idx < 0) {
      return Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.text1),
        children: [
          if (idx > 0) TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, idx + query.length),
            style: const TextStyle(color: C.teal, fontWeight: FontWeight.w800),
          ),
          if (idx + query.length < text.length)
            TextSpan(text: text.substring(idx + query.length)),
        ],
      ),
    );
  }
}
