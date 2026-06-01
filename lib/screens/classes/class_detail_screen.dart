import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';

class ClassDetailScreen extends StatefulWidget {
  final int classId;
  const ClassDetailScreen({super.key, required this.classId});
  @override State<ClassDetailScreen> createState() => _ClassDetailState();
}

class _ClassDetailState extends State<ClassDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<dynamic> _posts = [];
  List<dynamic> _assignments = [];
  List<dynamic> _mySubs = [];
  Map<String, dynamic> _rating = {};
  bool _loading = true, _loadingAsg = false;
  Set<int> _expandedCriteria = {};

  @override
  void initState() { super.initState(); _tabCtrl = TabController(length: 4, vsync: this); _tabCtrl.addListener(() { if (_tabCtrl.index == 2 && _assignments.isEmpty) _loadAssignments(); }); _load(); }

  Future<void> _load() async {
    if (!mounted) return; setState(() => _loading = true);
    final api = context.read<ApiService>();
    try { _posts = await api.getPosts(); } catch (_) {}
    if (!context.read<AuthProvider>().isTeacher) {
      try { _rating = await api.getMyRating(classId: widget.classId); } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadAssignments() async {
    if (!mounted) return; setState(() => _loadingAsg = true);
    final api = context.read<ApiService>();
    try {
      _assignments = await api.getAssignments(classId: widget.classId);
      if (!context.read<AuthProvider>().isTeacher) {
        try { _mySubs = await api.getMySubmissions(); } catch (_) {}
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingAsg = false);
  }

  Map<String, dynamic> get _meta {
    final p = _posts.firstWhere((p) => p['id'] == widget.classId && (() { try { return jsonDecode(p['body'])['type'] == 'class'; } catch (_) { return false; } })(), orElse: () => null);
    if (p == null) return {};
    try { return jsonDecode(p['body']); } catch (_) { return {}; }
  }
  String get _title => _posts.firstWhere((p) => p['id'] == widget.classId, orElse: () => {'title': 'Класс #${widget.classId}'})?['title'] ?? '';
  List<dynamic> get _lectures => _posts.where((p) => (p['title'] ?? '').startsWith('[LECTURE][${widget.classId}]')).toList();
  List<dynamic> get _materials => _posts.where((p) => (p['title'] ?? '').startsWith('[HW][${widget.classId}]')).toList();
  String _clean(String t) => t.replaceFirst(RegExp(r'^\[(LECTURE|HW)\]\[\d+\]\s*'), '').trim();
  String _preview(dynamic p) { try { final b = jsonDecode(p['body']); return (b['content'] ?? b['description'] ?? '').replaceAll(RegExp(r'https?://\S+'), '').replaceAll(RegExp(r'\s+'), ' ').trim(); } catch (_) { return ''; } }
  String _fmtDate(String? d) { if (d == null) return ''; try { final dt = DateTime.parse(d); return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year}'; } catch (_) { return d; } }
  String _code(int id) { const c = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; var s = ''; var n = id * 1337 + 42; for (var i = 0; i < 6; i++) { s += c[n % c.length]; n = n ~/ c.length + id * 7; } return s.substring(0, 6); }
  dynamic _subFor(int aId) => _mySubs.firstWhere((s) => s['assignment_id'] == aId, orElse: () => null);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final meta = _meta;
    final coverImg = meta['cover_image'];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = Theme.of(context).colorScheme.surface;

    if (_loading) return Scaffold(body: Center(child: CircularProgressIndicator(color: C.teal)));

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverAppBar(expandedHeight: 220, pinned: true, stretch: true,
            backgroundColor: isDark ? Color(0xFF0A1214) : Color(0xFF004D5A),
            leading: IconButton(icon: Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.arrow_back, color: Colors.white, size: 20)), onPressed: () => Navigator.pop(context)),
            actions: [
              IconButton(icon: Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.copy, color: Colors.white70, size: 18)), onPressed: () {
                final code = _code(widget.classId);
                Clipboard.setData(ClipboardData(text: code));
                showToast(context, 'Код: $code');
              }),
              if (auth.isTeacher) IconButton(icon: Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.edit, color: Colors.white70, size: 18)), onPressed: () => _editClass()),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              stretchModes: [StretchMode.zoomBackground],
              title: Text(_title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]), maxLines: 1, overflow: TextOverflow.ellipsis),
              titlePadding: EdgeInsets.only(left: 56, right: 56, bottom: 14),
              background: Stack(fit: StackFit.expand, children: [
                if (coverImg == null) Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF006475), C.teal], begin: Alignment.topLeft, end: Alignment.bottomRight))),
                if (coverImg != null && !coverImg.toString().startsWith('data:'))
                  Image.network(coverImg, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF006475), C.teal])))),
                if (coverImg != null && coverImg.toString().startsWith('data:'))
                  Builder(builder: (_) { try { return Image.memory(base64Decode(coverImg.toString().split(',').last), fit: BoxFit.cover); } catch (_) { return Container(color: C.teal); } }),
                Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.0, 0.4, 1.0], colors: [Colors.black38, Colors.transparent, Colors.black54]))),
                Positioned(bottom: 50, left: 16, right: 16, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (meta['description'] != null && meta['description'].toString().isNotEmpty)
                    Text(meta['description'], style: TextStyle(color: Colors.white70, fontSize: 13)),
                  SizedBox(height: 8),
                  GestureDetector(onTap: () { Clipboard.setData(ClipboardData(text: _code(widget.classId))); showToast(context, 'Код скопирован'); },
                    child: Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: adaptiveTealLt(context).withOpacity(0.9), borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.copy, size: 14, color: C.teal), SizedBox(width: 6), Text('Код: ', style: TextStyle(fontSize: 13, color: C.teal)), Text(_code(widget.classId), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: C.teal, letterSpacing: 2))]))),
                ])),
              ]),
            ),
          ),
        ],
        body: Column(children: [
          Container(
            color: surfaceColor,
            child: Column(children: [
              TabBar(
                controller: _tabCtrl,
                labelColor: C.teal,
                unselectedLabelColor: C.text4,
                indicatorColor: C.teal,
                indicatorWeight: 2.5,
                indicatorSize: TabBarIndicatorSize.label,
                labelPadding: EdgeInsets.symmetric(horizontal: 10),
                labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                unselectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                tabs: [
                  Tab(text: 'Лекции (${_lectures.length})'),
                  Tab(text: 'Материалы'),
                  Tab(text: 'Задания'),
                  Tab(text: 'AI Chat'),
                ],
              ),
              if (auth.isTeacher) AnimatedBuilder(animation: _tabCtrl, builder: (ctx, _) {
                if (_tabCtrl.index == 3) return SizedBox.shrink();
                return Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(children: [
                  Expanded(child: GestureDetector(onTap: () => _createAssignment(),
                    child: Container(padding: EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: C.teal.withOpacity(0.3))),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.assignment_add, size: 16, color: C.teal), SizedBox(width: 6),
                        Text('Задание', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.teal))])))),
                  SizedBox(width: 10),
                  Expanded(child: GestureDetector(onTap: () => _showAddMenu(),
                    child: Container(padding: EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(gradient: LinearGradient(colors: [C.teal, C.tealDk]), borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: C.teal.withOpacity(0.3), blurRadius: 8, offset: Offset(0, 3))]),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add, size: 16, color: Colors.white), SizedBox(width: 6),
                        Text('Добавить', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white))])))),
                ]),
              );
              }),
            ]),
          ),
          Expanded(child: TabBarView(controller: _tabCtrl, children: [
            _postList(_lectures, 'lecture'),
            _postList(_materials, 'material'),
            _assignmentsTab(auth),
            _aiTab(),
          ])),
        ]),
      ),
      floatingActionButton: null,
    );
  }

  // ── Posts list ──
  Widget _postList(List<dynamic> posts, String type) {
    final surface = Theme.of(context).colorScheme.surface;
    final isTeacher = context.read<AuthProvider>().isTeacher;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (posts.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 72, height: 72, decoration: BoxDecoration(color: C.teal.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(type == 'lecture' ? Icons.menu_book_rounded : Icons.inventory_2_outlined, size: 32, color: C.teal)),
      SizedBox(height: 16),
      Text(type == 'lecture' ? 'Лекций ещё нет' : 'Материалов ещё нет', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: C.text4)),
    ]));
    return ListView.builder(padding: EdgeInsets.fromLTRB(12, 12, 12, 90), itemCount: posts.length, itemBuilder: (ctx, i) {
      final p = posts[i]; final files = _extractFiles(p);
      final body = _preview(p);
      final num = posts.length - i;
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: Duration(milliseconds: 250 + i * 50),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => Transform.translate(offset: Offset(0, 16 * (1 - t)), child: Opacity(opacity: t, child: child)),
        child: GestureDetector(
          onTap: () => _showPost(p, type),
          child: Container(
            margin: EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.05), blurRadius: 12, offset: Offset(0, 3))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 52, height: 52,
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [C.teal.withOpacity(0.15), C.teal.withOpacity(0.05)]), borderRadius: BorderRadius.circular(16)),
                  child: Stack(alignment: Alignment.center, children: [
                    Icon(Icons.menu_book_rounded, color: C.teal, size: 22),
                    Positioned(bottom: 4, right: 4, child: Container(width: 18, height: 18,
                      decoration: BoxDecoration(color: C.teal, shape: BoxShape.circle),
                      child: Center(child: Text('$num', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900))))),
                  ])),
                SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${type == 'lecture' ? 'Лекция' : 'Материал'} $num',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.teal, letterSpacing: 0.5)),
                  SizedBox(height: 3),
                  Text(_clean(p['title'] ?? ''), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (body.isNotEmpty) Padding(padding: EdgeInsets.only(top: 4),
                    child: Text(body, style: TextStyle(fontSize: 13, color: C.text4, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis)),
                ])),
                if (isTeacher) Column(children: [
                  _iconBtn(Icons.edit_outlined, () => _editPost(p)),
                  SizedBox(height: 4),
                  _iconBtn(Icons.delete_outline, () async { try { await context.read<ApiService>().deletePost(p['id']); _load(); } catch (_) {} }),
                ]),
              ])),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: adaptiveSurface2(context).withOpacity(0.5), borderRadius: BorderRadius.vertical(bottom: Radius.circular(20))),
                child: Row(children: [
                  Icon(Icons.calendar_today_outlined, size: 12, color: C.text4), SizedBox(width: 4),
                  Text(_fmtDate(p['created_at'] ?? ''), style: TextStyle(fontSize: 12, color: C.text4)),
                  if (files.isNotEmpty) ...[
                    SizedBox(width: 10),
                    Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: C.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.attach_file, size: 11, color: C.teal), SizedBox(width: 3),
                        Text('${files.length} файл', style: TextStyle(fontSize: 11, color: C.teal, fontWeight: FontWeight.w600))])),
                  ],
                  Spacer(),
                  Row(children: [
                    Text('Открыть', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.teal)),
                    SizedBox(width: 4), Icon(Icons.arrow_forward_ios, size: 12, color: C.teal),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      );
    });
  }


  Widget _iconBtn(IconData ic, VoidCallback onTap) => GestureDetector(onTap: onTap,
    child: Container(width: 34, height: 34, decoration: BoxDecoration(color: C.teal.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
      child: Icon(ic, size: 17, color: C.text4)));

  void _editPost(dynamic p) {
    final tc = TextEditingController(text: _clean(p['title'] ?? ''));
    final cc = TextEditingController(text: (() { try { return jsonDecode(p['body'])['content'] ?? ''; } catch (_) { return p['body'] ?? ''; } })());
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2))),
          SizedBox(height: 20), Text('Edit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          SizedBox(height: 16), TextField(controller: tc, decoration: InputDecoration(labelText: 'Title')),
          SizedBox(height: 12), TextField(controller: cc, decoration: InputDecoration(labelText: 'Content'), maxLines: 5),
          SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel'))),
            SizedBox(width: 12),
            Expanded(child: ElevatedButton(onPressed: () async {
              try {
                final prefix = (p['title'] ?? '').startsWith('[LECTURE]') ? '[LECTURE][${widget.classId}] ' : '[HW][${widget.classId}] ';
                await context.read<ApiService>().updatePost(p['id'], '$prefix${tc.text.trim()}', jsonEncode({'content': cc.text}));
                Navigator.pop(ctx); _load(); showToast(context, 'Updated');
              } catch (_) { showToast(context, 'Error', error: true); }
            }, child: Text('Save'))),
          ]),
        ])));
  }

  List<String> _extractFiles(dynamic p) {
    try {
      final b = jsonDecode(p['body'] ?? '');
      if (b['files'] is List && (b['files'] as List).isNotEmpty) {
        return (b['files'] as List).map((f) => _fixFileUrl(f.toString())).toList();
      }
    } catch (_) {}
    final body = p['body'] ?? '';
    final matches = RegExp(r'https?://[^\s"<>]+\.(pdf|doc|docx|txt|png|jpg|jpeg|pptx?|xlsx?)', caseSensitive: false).allMatches(body);
    return matches.map((m) => _fixFileUrl(m.group(0)!)).toList();
  }

  /// Fix localhost/127.0.0.1 URLs to use the actual API base URL
  String _fixFileUrl(String url) {
    final api = context.read<ApiService>();
    final base = api.baseUrl; // e.g. http://10.0.2.2:8000
    return url
        .replaceAll(RegExp(r'https?://localhost:\d+'), base)
        .replaceAll(RegExp(r'https?://127\.0\.0\.1:\d+'), base);
  }

  /// Remove raw file URLs from content for cleaner display
  String _cleanContent(String content) {
    return content
        .replaceAll(RegExp(r'https?://[^\s"<>]+\.(pdf|doc|docx|txt|png|jpg|jpeg|pptx?|xlsx?)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// Extract file URLs from plain text
  List<String> _extractFilesFromText(String text) {
    final matches = RegExp(r'https?://[^\s"<>]+\.(pdf|doc|docx|txt|png|jpg|jpeg|pptx?|xlsx?)', caseSensitive: false).allMatches(text);
    return matches.map((m) => _fixFileUrl(m.group(0)!)).toList();
  }

  // ── Assignments tab ──
  Widget _assignmentsTab(AuthProvider auth) {
    if (_loadingAsg) return Center(child: CircularProgressIndicator(color: C.teal, strokeWidth: 2.5));
    final surface = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avg = (_rating['avg_score'] ?? 0).round();
    final pct = (_rating['avg_percent'] ?? 0).round();

    return ListView(padding: EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
      // Rating + Next Deadline side by side (students)
      if (!auth.isTeacher && _rating.isNotEmpty) Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Rating card
          Expanded(child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF006475), C.teal], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('МОЙ РЕЙТИНГ', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
              SizedBox(height: 8),
              RichText(text: TextSpan(children: [
                TextSpan(text: '$avg', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, height: 1)),
                TextSpan(text: ' /100', style: TextStyle(color: Colors.white60, fontSize: 14, fontWeight: FontWeight.w600)),
              ])),
              SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
                value: avg / 100, backgroundColor: Colors.white24, color: Colors.white, minHeight: 4)),
              SizedBox(height: 4),
              Text('Успеваемость: $pct%', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
            ]),
          )),
          SizedBox(width: 10),
          // Next deadline card
          Expanded(child: Builder(builder: (_) {
            final now = DateTime.now();
            final upcoming = _assignments.where((a) {
              if (a['deadline'] == null) return false;
              final dl = DateTime.tryParse(a['deadline']);
              if (dl == null) return false;
              final sub = _subFor(a['id']);
              return dl.isAfter(now) && (sub == null || sub['status'] != 'graded');
            }).toList();
            upcoming.sort((a, b) => (a['deadline'] ?? '').compareTo(b['deadline'] ?? ''));
            if (upcoming.isEmpty) return Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: adaptiveBorder(context))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('СЛЕД. ДЕДЛАЙН', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                SizedBox(height: 16),
                Center(child: Icon(Icons.check_circle_outline, size: 32, color: C.green)),
                SizedBox(height: 8),
                Center(child: Text('Всё сдано!', style: TextStyle(fontSize: 13, color: C.green, fontWeight: FontWeight.w600))),
              ]));
            final next = upcoming.first;
            final dl = DateTime.parse(next['deadline']);
            final diff = dl.difference(now);
            final days = diff.inDays;
            final hours = diff.inHours % 24;
            final months = ['ЯНВ','ФЕВ','МАР','АПР','МАЙ','ИЮН','ИЮЛ','АВГ','СЕН','ОКТ','НОЯ','ДЕК'];
            final remaining = days > 0 ? '$days дн. $hours ч.' : '$hours ч. ${diff.inMinutes % 60} мин.';
            return Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: adaptiveBorder(context))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('СЛЕД. ДЕДЛАЙН', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                SizedBox(height: 10),
                Row(children: [
                  Container(
                    width: 48, height: 56,
                    decoration: BoxDecoration(color: adaptiveTealLt(context), borderRadius: BorderRadius.circular(10)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(months[dl.month - 1], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: C.teal, letterSpacing: 1)),
                      Text('${dl.day}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: C.teal, height: 1.1)),
                    ]),
                  ),
                  SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(next['title'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    SizedBox(height: 2),
                    Text('Осталось: $remaining', style: TextStyle(fontSize: 11, color: days <= 1 ? C.red : C.teal, fontWeight: FontWeight.w500)),
                  ])),
                ]),
              ]),
            );
          })),
        ])),
      ),
      Row(children: [
        Text('Задания', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        Spacer(),
        Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [Icon(Icons.sort_rounded, size: 14, color: C.text4), SizedBox(width: 4), Text('По дедлайну', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.text4))])),
      ]),
      SizedBox(height: 12),
      if (_assignments.isEmpty) Container(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: Column(children: [
        Container(width: 64, height: 64, decoration: BoxDecoration(color: C.teal.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(Icons.assignment_outlined, size: 30, color: C.teal)),
        SizedBox(height: 12),
        Text('Нет заданий', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.text4)),
      ]))),
      // Assignment cards
      ..._assignments.asMap().entries.map((entry) {
        final i = entry.key; final a = entry.value;
        final sub = _subFor(a['id']);
        final status = sub?['status'];
        final grade = sub?['grade'];
        final isGraded = status == 'graded';
        final isSubmitted = status == 'submitted';
        final deadline = a['deadline'];
        final isLate = deadline != null && DateTime.tryParse(deadline)?.isBefore(DateTime.now()) == true && sub == null;

        Color statusColor = isGraded ? C.green : isSubmitted ? C.teal : isLate ? C.red : C.text4;
        Color statusBg = isGraded ? C.greenLt : isSubmitted ? adaptiveTealLt(context) : isLate ? C.redLt : adaptiveSurface2(context);
        String statusText = isGraded ? 'ОЦЕНЕНО' : isSubmitted ? 'СДАНО' : isLate ? 'ПРОСРОЧЕНО' : 'НОВОЕ';
        IconData statusIcon = isGraded ? Icons.check_circle_rounded : isSubmitted ? Icons.upload_file : isLate ? Icons.schedule_rounded : Icons.edit_note_rounded;

        return TweenAnimationBuilder<double>(
          key: ValueKey(a['id']),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 250 + i * 60),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Transform.translate(offset: Offset(0, 16 * (1 - t)), child: Opacity(opacity: t, child: child)),
          child: GestureDetector(
            onTap: () => _showAssignment(a, sub),
            child: Container(
              margin: EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.04), blurRadius: 10, offset: Offset(0, 2))],
              ),
              child: Column(children: [
                Padding(padding: EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 48, height: 48,
                    decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                    child: Icon(statusIcon, color: statusColor, size: 22)),
                  SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(a['title'] ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis)),
                      SizedBox(width: 8),
                      Container(padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)),
                        child: Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: statusColor))),
                    ]),
                    if (a['description'] != null && a['description'].toString().isNotEmpty)
                      Padding(padding: EdgeInsets.only(top: 4),
                        child: Text(a['description'], style: TextStyle(fontSize: 13, color: C.text4), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    SizedBox(height: 10),
                    Wrap(spacing: 12, children: [
                      if (deadline != null) Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.calendar_today_outlined, size: 12, color: isLate ? C.red : C.text4), SizedBox(width: 4),
                        Text(_fmtDate(deadline), style: TextStyle(fontSize: 12, color: isLate ? C.red : C.text4, fontWeight: FontWeight.w500)),
                      ]),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.star_rounded, size: 14, color: C.teal), SizedBox(width: 3),
                        Text('${a['max_score'] ?? 100} баллов', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.teal)),
                      ]),
                      if (grade != null) Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_circle_rounded, size: 12, color: C.green), SizedBox(width: 3),
                        Text('${grade['score']}/${a['max_score']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: C.green)),
                      ]),
                    ]),
                  ])),
                ])),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(color: adaptiveSurface2(context).withOpacity(0.4), borderRadius: BorderRadius.vertical(bottom: Radius.circular(18))),
                  child: Row(children: [
                    Icon(Icons.touch_app_outlined, size: 13, color: C.text4), SizedBox(width: 4),
                    Text('Нажмите для подробностей', style: TextStyle(fontSize: 12, color: C.text4)),
                    Spacer(),
                    Icon(Icons.arrow_forward_ios, size: 12, color: C.teal),
                  ]),
                ),
              ]),
            ),
          ),
        );
      }),
    ]);
  }


  // ── AI Chat tab ──
  Widget _aiTab() => _AiChat(classId: widget.classId, className: _title);

  // ── Show post detail ──
  void _showPost(dynamic p, String type) {
    String content = ''; try { final b = jsonDecode(p['body']); content = b['content'] ?? b['description'] ?? ''; } catch (_) { content = p['body'] ?? ''; }
    final files = _extractFiles(p);
    final cleanText = _cleanContent(content);
    showModalBottomSheet(context: context, isScrollControlled: true, shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(expand: false, initialChildSize: 0.7, maxChildSize: 0.95, builder: (ctx, sc) => ListView(controller: sc, padding: EdgeInsets.all(20), children: [
        Center(child: Container(width: 40, height: 4, margin: EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2)))),
        Text(_clean(p['title'] ?? ''), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        SizedBox(height: 6), Text(_fmtDate(p['created_at'] ?? ''), style: TextStyle(fontSize: 12, color: C.text4)),
        if (cleanText.isNotEmpty) ...[SizedBox(height: 16), Text(cleanText, style: TextStyle(fontSize: 14, height: 1.7))],
        if (files.isNotEmpty) ...[SizedBox(height: 16), Text('Прикреплённые файлы', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.text3)), SizedBox(height: 8),
          ...files.map((f) {
            final name = Uri.parse(f).pathSegments.last;
            final ext = name.split('.').last.toLowerCase();
            final icon = ext == 'pdf' ? Icons.picture_as_pdf : ext == 'pptx' || ext == 'ppt' ? Icons.slideshow : ext == 'doc' || ext == 'docx' ? Icons.description : ext == 'xlsx' || ext == 'xls' ? Icons.table_chart : Icons.insert_drive_file;
            return GestureDetector(
              onTap: () async {
                final uri = Uri.parse(f);
                try { await launchUrl(uri, mode: LaunchMode.inAppBrowserView); } catch (_) {}
              },
              child: Container(margin: EdgeInsets.only(bottom: 8), padding: EdgeInsets.all(14), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: adaptiveBorder(context))),
                child: Row(children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(color: adaptiveTealLt(context), borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, size: 20, color: C.teal)),
                  SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    Text(ext.toUpperCase(), style: TextStyle(fontSize: 11, color: C.text4)),
                  ])),
                  Icon(Icons.open_in_new_rounded, size: 16, color: C.teal),
                ])));
          }),
        ],
      ])));
  }

  // ── Show assignment detail ──
  void _showAssignment(dynamic a, dynamic sub) {
    final tc = TextEditingController(); bool busy = false;
    final auth = context.read<AuthProvider>();
    final isTeacherOrAdmin = auth.isTeacher;
    List<dynamic> criteria = []; try { criteria = jsonDecode(a['criteria'] ?? '[]'); } catch (_) {}
    // Student file attachment state
    List<PlatformFile> pickedFiles = [];

    showModalBottomSheet(context: context, isScrollControlled: true, shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(expand: false, initialChildSize: 0.85, maxChildSize: 0.95, builder: (ctx, sc) => ListView(controller: sc, padding: EdgeInsets.all(20), children: [
        Center(child: Container(width: 40, height: 4, margin: EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2)))),
        Text(a['title'] ?? '', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          _chip(Icons.star, '${a['max_score'] ?? 100} баллов', C.teal, adaptiveTealLt(context)),
          if (a['deadline'] != null) _chip(Icons.calendar_today, _fmtDate(a['deadline']), C.text4, adaptiveSurface2(context)),
        ]),
        if (a['description'] != null && _cleanContent(a['description'].toString()).isNotEmpty) ...[
          SizedBox(height: 16),
          Text(_cleanContent(a['description'].toString()), style: TextStyle(fontSize: 14, height: 1.6)),
        ],
        // Attached files: from file_urls field OR legacy regex in description
        ...() {
          List<String> fromField = [];
          final raw = a['file_urls'];
          if (raw is List) {
            fromField = raw.map((f) => _fixFileUrl(f.toString())).toList();
          } else if (raw is String && raw.isNotEmpty) {
            try { fromField = (jsonDecode(raw) as List).map((f) => _fixFileUrl(f.toString())).toList(); } catch (_) {}
          }
          final fromDesc = a['description'] != null ? _extractFilesFromText(a['description'].toString()) : <String>[];
          final allFiles = {...fromField, ...fromDesc}.toList();
          if (allFiles.isEmpty) return <Widget>[];
          return [
            SizedBox(height: 16),
            Text('Прикреплённые файлы', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.text3)),
            SizedBox(height: 8),
            ...allFiles.map((f) {
              final name = Uri.parse(f).pathSegments.last;
              final ext = name.split('.').last.toLowerCase();
              final icon = ext == 'pdf' ? Icons.picture_as_pdf : ext == 'pptx' || ext == 'ppt' ? Icons.slideshow : ext == 'doc' || ext == 'docx' ? Icons.description : Icons.insert_drive_file;
              return GestureDetector(
                onTap: () async { final uri = Uri.parse(f); try { await launchUrl(uri, mode: LaunchMode.inAppBrowserView); } catch (_) {} },
                child: Container(margin: EdgeInsets.only(bottom: 8), padding: EdgeInsets.all(12), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: adaptiveBorder(context))),
                  child: Row(children: [
                    Container(width: 36, height: 36, decoration: BoxDecoration(color: adaptiveTealLt(context), borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 18, color: C.teal)),
                    SizedBox(width: 10),
                    Expanded(child: Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    Icon(Icons.open_in_new_rounded, size: 14, color: C.teal),
                  ])));
            }),
          ];
        }(),
        // Criteria: collapsible for teachers/admins
        if (isTeacherOrAdmin && criteria.isNotEmpty) ...[
          SizedBox(height: 16),
          GestureDetector(
            onTap: () => setS(() { if (_expandedCriteria.contains(a['id'])) _expandedCriteria.remove(a['id']); else _expandedCriteria.add(a['id']); }),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: adaptiveTealLt(context), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(Icons.rule_rounded, size: 16, color: C.teal),
                SizedBox(width: 8),
                Text('Критерии оценивания', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.teal)),
                SizedBox(width: 4),
                Text('(${criteria.length})', style: TextStyle(fontSize: 12, color: C.text4)),
                Spacer(),
                AnimatedRotation(turns: _expandedCriteria.contains(a['id']) ? 0.5 : 0.0, duration: Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: C.teal)),
              ]),
            ),
          ),
          AnimatedSize(duration: Duration(milliseconds: 300), curve: Curves.easeInOut,
            child: _expandedCriteria.contains(a['id']) ? Column(children: [
              SizedBox(height: 8),
              ...criteria.map((c) => Container(margin: EdgeInsets.only(bottom: 8), padding: EdgeInsets.all(12), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c['name'] ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  if (c['description'] != null && c['description'].toString().isNotEmpty)
                    Padding(padding: EdgeInsets.only(top: 4), child: Text(c['description'], style: TextStyle(fontSize: 12, color: C.text4))),
                ])),
                  Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: adaptiveTealLt(context), borderRadius: BorderRadius.circular(8)),
                    child: Text('${c['weight'] ?? 0}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.teal)))])))
            ]) : SizedBox.shrink(),
          ),
        ],
        // Grade result (students see their grade) — FULL FEEDBACK
        if (sub?['grade'] != null) ...[
          SizedBox(height: 16),
          // Main score card
          Container(padding: EdgeInsets.all(18), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: adaptiveBorder(context))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                RichText(text: TextSpan(children: [
                  TextSpan(text: '${sub['grade']['score']}', style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: C.teal, height: 1)),
                  TextSpan(text: ' / ${a['max_score']}', style: TextStyle(fontSize: 18, color: C.text4, fontWeight: FontWeight.w600)),
                ])),
                Spacer(),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${(sub['grade']['score'] / (a['max_score'] ?? 100) * 100).round()}%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: adaptiveText1(context))),
                  SizedBox(height: 4),
                  Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: C.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(sub['grade']['graded_by'] == 'ai' ? Icons.bolt : Icons.person, size: 14, color: C.teal),
                      SizedBox(width: 4),
                      Text(sub['grade']['graded_by'] == 'ai' ? 'ИИ-проверка' : 'Учитель', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.teal)),
                    ])),
                ]),
              ]),
              // Feedback text
              if (sub['grade']['feedback'] != null) ...[
                SizedBox(height: 14),
                Text('ФИДБЕК', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                SizedBox(height: 6),
                Text(sub['grade']['feedback'], style: TextStyle(fontSize: 14, color: adaptiveText1(context), height: 1.6)),
              ],
            ])),
          // Criteria scores breakdown
          if (sub['grade']['criteria_scores'] != null) ...[
            SizedBox(height: 12),
            Text('ПО КРИТЕРИЯМ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
            SizedBox(height: 8),
            ...(() {
              List<dynamic> criteriaScores = [];
              try { criteriaScores = jsonDecode(sub['grade']['criteria_scores']); } catch (_) {
                if (sub['grade']['criteria_scores'] is List) criteriaScores = sub['grade']['criteria_scores'];
              }
              return criteriaScores.map<Widget>((cs) {
                final score = (cs['score'] ?? 0) as num;
                final maxScore = (cs['max_score'] ?? cs['max'] ?? cs['weight'] ?? 100) as num;
                final pct = maxScore > 0 ? score / maxScore : 0.0;
                return Container(margin: EdgeInsets.only(bottom: 8), padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(cs['name'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                      RichText(text: TextSpan(children: [
                        TextSpan(text: '${score.toInt()}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.teal)),
                        TextSpan(text: ' / ${maxScore.toInt()}', style: TextStyle(fontSize: 13, color: C.text4)),
                      ])),
                    ]),
                    if (cs['comment'] != null || cs['feedback'] != null)
                      Padding(padding: EdgeInsets.only(top: 6), child: Text(cs['comment'] ?? cs['feedback'] ?? '', style: TextStyle(fontSize: 13, color: C.text4, height: 1.5))),
                    SizedBox(height: 8),
                    ClipRRect(borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(value: pct.toDouble(), backgroundColor: adaptiveBorder(context), color: C.teal, minHeight: 4)),
                  ]));
              }).toList();
            })(),
          ],
        ],
        // AI grading in progress
        if (sub != null && sub['status'] == 'grading' && sub['grade'] == null) ...[
          SizedBox(height: 16),
          Container(padding: EdgeInsets.all(14), decoration: BoxDecoration(color: C.teal.withOpacity(0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: C.teal.withOpacity(0.15))),
            child: Row(children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: C.teal)),
              SizedBox(width: 12),
              Expanded(child: Text('ИИ проверяет вашу работу...', style: TextStyle(fontSize: 13, color: C.teal, fontWeight: FontWeight.w500))),
            ])),
        ],
        // Student answer preview (if submitted)
        if (sub != null && sub['text_content'] != null) ...[
          SizedBox(height: 16),
          Text('ВАШ ОТВЕТ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
          SizedBox(height: 6),
          Container(padding: EdgeInsets.all(12), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12)),
            child: Text(sub['text_content'], style: TextStyle(fontSize: 13, height: 1.6), maxLines: 5, overflow: TextOverflow.ellipsis)),
        ],
        // Retract button (students, submitted but not graded)
        if (!isTeacherOrAdmin && sub != null && sub['status'] != 'graded') ...[
          SizedBox(height: 12),
          GestureDetector(
            onTap: busy ? null : () async {
              setS(() => busy = true);
              try {
                await context.read<ApiService>().retractSubmission(sub['id']);
                Navigator.pop(ctx);
                showToast(context, 'Сдача отозвана — можно отправить заново');
                _loadAssignments();
              } catch (_) {
                showToast(context, 'Ошибка', error: true);
              }
              setS(() => busy = false);
            },
            child: Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.replay, size: 14, color: C.text4),
                SizedBox(width: 6),
                Text(busy ? 'Отзыв...' : 'Отозвать и сдать заново', style: TextStyle(fontSize: 13, color: C.text4)),
              ])),
          ),
        ],
        // Submit block (students, not yet submitted)
        if (!isTeacherOrAdmin && sub == null) ...[
          SizedBox(height: 20),
          Divider(),
          SizedBox(height: 12),
          Text('Отправить работу', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          SizedBox(height: 10),
          TextField(controller: tc, maxLines: 4, decoration: InputDecoration(hintText: 'Текст работы или ссылка (необязательно)...')),
          SizedBox(height: 12),
          // File picker button
          GestureDetector(
            onTap: () async {
              final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
              if (result != null) setS(() => pickedFiles = result.files);
            },
            child: Container(padding: EdgeInsets.all(14), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(14), border: Border.all(color: C.teal.withOpacity(0.3), width: 1.5)),
              child: Row(children: [
                Icon(Icons.attach_file, color: C.teal, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text(pickedFiles.isEmpty ? 'Прикрепить файлы' : 'Файлов выбрано: ${pickedFiles.length}', style: TextStyle(fontSize: 14, color: pickedFiles.isEmpty ? C.text4 : C.teal, fontWeight: pickedFiles.isEmpty ? FontWeight.normal : FontWeight.w600))),
                Icon(Icons.chevron_right, color: C.text4, size: 18),
              ])),
          ),
          // Show picked file names
          if (pickedFiles.isNotEmpty) ...[
            SizedBox(height: 8),
            ...pickedFiles.map((f) => Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(Icons.insert_drive_file_outlined, size: 14, color: C.teal),
                SizedBox(width: 6),
                Expanded(child: Text(f.name, style: TextStyle(fontSize: 12, color: C.text3), overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: () => setS(() => pickedFiles.removeWhere((x) => x.name == f.name)),
                  child: Icon(Icons.close, size: 14, color: C.text4)),
              ]),
            )),
          ],
          SizedBox(height: 16),
          SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
            onPressed: busy ? null : () async {
              if (tc.text.trim().isEmpty && pickedFiles.isEmpty) {
                showToast(context, 'Добавьте текст или прикрепите файлы', error: true);
                return;
              }
              setS(() => busy = true);
              try {
                final api = context.read<ApiService>();
                // Upload files first, collect URLs
                final fileUrls = <String>[];
                for (final pf in pickedFiles) {
                  if (pf.path != null) {
                    try {
                      final res = await api.uploadFile(pf.path!, pf.name);
                      final url = res['url'] ?? res['file_url'] ?? res['path'];
                      if (url != null) fileUrls.add(url.toString());
                    } catch (_) {}
                  }
                }
                await api.submitAssignment(a['id'], {
                  if (tc.text.trim().isNotEmpty) 'text_content': tc.text.trim(),
                  if (fileUrls.isNotEmpty) 'file_urls': fileUrls,
                });
                Navigator.pop(ctx);
                showToast(context, 'Работа отправлена!');
                _loadAssignments();
              } catch (_) {
                showToast(context, 'Ошибка отправки', error: true);
              }
              setS(() => busy = false);
            },
            child: busy ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Отправить'),
          )),
        ],
        // Teacher: view submissions
        if (isTeacherOrAdmin) ...[SizedBox(height: 16), SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(icon: Icon(Icons.list_alt, size: 18), label: Text('Просмотр работ'), onPressed: () => _viewSubs(a['id'])))],
        SizedBox(height: 24),
      ]))));
  }

  Widget _chip(IconData ic, String text, Color fg, Color bg) => Container(
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(ic, size: 14, color: fg), SizedBox(width: 4), Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg))]));

  void _viewSubs(int aId) async {
    try {
      final subs = await context.read<ApiService>().getSubmissions(aId);
      if (!mounted) return;
      final graded = subs.where((s) => s['status'] == 'graded').length;
      final pending = subs.length - graded;
      showModalBottomSheet(context: context, isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) {
          String search = '';
          dynamic selectedSub;
          return StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(expand: false, initialChildSize: 0.85, maxChildSize: 0.95, builder: (ctx, sc) {
            // Detail view for selected student
            if (selectedSub != null) {
              final name = selectedSub['student_name'] ?? '#${selectedSub['student_id']}';
              final initials = name.length >= 2 ? '${name[0]}${name.split(' ').length > 1 ? name.split(' ').last[0] : name[1]}'.toUpperCase() : name[0].toUpperCase();
              final grade = selectedSub['grade'];
              final score = grade?['score'];
              final feedback = grade?['feedback'];
              final criteria = grade?['criteria'] as List<dynamic>? ?? [];
              final files = selectedSub['files'] as List<dynamic>? ?? [];
              return ListView(controller: sc, padding: EdgeInsets.all(20), children: [
                Center(child: Container(width: 40, height: 4, margin: EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2)))),
                // Back button
                GestureDetector(onTap: () => setS(() => selectedSub = null),
                  child: Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.arrow_back, size: 16, color: C.text4), SizedBox(width: 6), Text('Назад к списку', style: TextStyle(fontSize: 13, color: C.text4))]))),
                SizedBox(height: 16),
                // Student info
                Row(children: [
                  CircleAvatar(radius: 22, backgroundColor: C.teal.withOpacity(0.15), child: Text(initials, style: TextStyle(color: C.teal, fontWeight: FontWeight.w800, fontSize: 14))),
                  SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(selectedSub['submitted_at'] != null ? _fmtDate(selectedSub['submitted_at']) : '', style: TextStyle(fontSize: 12, color: C.text4)),
                  ])),
                ]),
                // Attached files
                if (files.isNotEmpty || selectedSub['text_content'] != null) ...[
                  SizedBox(height: 16),
                  Text('ПРИКРЕПЛЁННЫЕ ФАЙЛЫ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                  SizedBox(height: 8),
                  if (selectedSub['text_content'] != null) Container(padding: EdgeInsets.all(12), margin: EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(color: C.teal.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                    child: Text(selectedSub['text_content'], style: TextStyle(fontSize: 13), maxLines: 3, overflow: TextOverflow.ellipsis)),
                  ...files.map((f) => Container(padding: EdgeInsets.all(12), margin: EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(color: C.teal.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [Icon(Icons.description, size: 18, color: C.teal), SizedBox(width: 8), Expanded(child: Text(f['filename'] ?? f.toString(), style: TextStyle(fontSize: 13, color: C.teal)))]))),
                ],
                // Score
                if (score != null) ...[
                  SizedBox(height: 20),
                  Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(16)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        RichText(text: TextSpan(children: [
                          TextSpan(text: '$score', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: C.teal)),
                          TextSpan(text: ' / 100', style: TextStyle(fontSize: 16, color: C.text4)),
                        ])),
                        Spacer(),
                        Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: C.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.bolt, size: 14, color: C.teal), SizedBox(width: 4), Text('ИИ-проверка', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.teal))])),
                      ]),
                      if (feedback != null) ...[
                        SizedBox(height: 12),
                        Text('ФИДБЕК', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                        SizedBox(height: 6),
                        Text(feedback, style: TextStyle(fontSize: 14, height: 1.6)),
                      ],
                    ])),
                  // Per-criteria breakdown
                  if (criteria.isNotEmpty) ...[
                    SizedBox(height: 16),
                    Text('ПО КРИТЕРИЯМ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                    SizedBox(height: 8),
                    ...criteria.map((c) => Container(margin: EdgeInsets.only(bottom: 8), padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(14)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(c['name'] ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                          RichText(text: TextSpan(children: [
                            TextSpan(text: '${c['score'] ?? 0}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.teal)),
                            TextSpan(text: ' / ${c['max_score'] ?? c['weight'] ?? 0}', style: TextStyle(fontSize: 13, color: C.text4)),
                          ])),
                        ]),
                        if (c['feedback'] != null) Padding(padding: EdgeInsets.only(top: 6), child: Text(c['feedback'], style: TextStyle(fontSize: 13, color: C.text4, height: 1.5))),
                      ]))),
                  ],
                  SizedBox(height: 16),
                  // Re-grade button
                  SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
                    icon: Icon(Icons.bolt, size: 18, color: Colors.white),
                    label: Text('Перепроверить ИИ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () async {
                      try { await context.read<ApiService>().aiGrade(selectedSub['id']); showToast(context, 'Перепроверка запущена'); } catch (_) { showToast(context, 'Ошибка', error: true); }
                    },
                  )),
                ] else ...[
                  SizedBox(height: 20),
                  SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
                    icon: Icon(Icons.bolt, size: 18, color: Colors.white),
                    label: Text('Оценить ИИ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    onPressed: () async {
                      try { await context.read<ApiService>().aiGrade(selectedSub['id']); showToast(context, 'Оценка запущена'); } catch (_) { showToast(context, 'Ошибка', error: true); }
                    },
                  )),
                ],
                SizedBox(height: 24),
              ]);
            }
            // Student list
            final filtered = subs.where((s) => search.isEmpty || (s['student_name'] ?? '').toLowerCase().contains(search.toLowerCase())).toList();
            return ListView(controller: sc, padding: EdgeInsets.all(20), children: [
              Center(child: Container(width: 40, height: 4, margin: EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2)))),
              Row(children: [
                _statBox('${subs.length}', 'Всего', adaptiveText1(context)),
                SizedBox(width: 8),
                _statBox('$graded', 'Проверено', C.teal),
                SizedBox(width: 8),
                _statBox('$pending', 'Ожидают', C.red),
              ]),
              SizedBox(height: 16),
              TextField(decoration: InputDecoration(hintText: 'Поиск по ФИО студента...', prefixIcon: Icon(Icons.search, size: 18, color: C.text4), contentPadding: EdgeInsets.symmetric(vertical: 10)),
                onChanged: (v) => setS(() => search = v)),
              SizedBox(height: 12),
              ...filtered.map((s) {
                final name = s['student_name'] ?? s['student_email'] ?? '#${s['student_id']}';
                final initials = name.length >= 2 ? '${name[0]}${name.split(' ').length > 1 ? name.split(' ').last[0] : name[1]}'.toUpperCase() : name[0].toUpperCase();
                final score = s['grade']?['score'];
                final isGraded = s['status'] == 'graded';
                return GestureDetector(onTap: () => setS(() => selectedSub = s),
                  child: Container(margin: EdgeInsets.only(bottom: 8), padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      CircleAvatar(radius: 20, backgroundColor: C.teal.withOpacity(0.15), child: Text(initials, style: TextStyle(color: C.teal, fontWeight: FontWeight.w800, fontSize: 13))),
                      SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text(s['submitted_at'] != null ? _fmtDate(s['submitted_at']) : '', style: TextStyle(fontSize: 11, color: C.text4)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        if (score != null) Text('$score/100', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.teal))
                        else Text('—', style: TextStyle(fontSize: 16, color: C.text4)),
                        Text(isGraded ? 'Оценено' : 'Ожидает', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isGraded ? C.teal : C.yellow)),
                      ]),
                    ])));
              }),
            ]);
          }));
        });
    } catch (_) { showToast(context, 'Ошибка загрузки', error: true); }
  }

  Widget _statBox(String val, String label, Color color) => Expanded(child: Container(
    padding: EdgeInsets.all(14), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.2))),
    child: Column(children: [Text(val, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)), SizedBox(height: 2), Text(label, style: TextStyle(fontSize: 11, color: C.text4))])));

  // ── FAB menu ──
  void _showAddMenu() {
    String type = 'lecture';
    final tc = TextEditingController(), cc = TextEditingController();
    List<PlatformFile> lectureFiles = [];
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2))),
          SizedBox(height: 16),
          // Header
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: C.teal.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.menu_book_rounded, color: C.teal, size: 22)),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Добавить лекцию', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text('Учебный материал для класса', style: TextStyle(fontSize: 12, color: C.text4)),
            ])),
            IconButton(icon: Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ]),
          SizedBox(height: 20),
          // Type toggle
          Container(decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Expanded(child: GestureDetector(onTap: () => setS(() => type = 'lecture'),
                child: Container(padding: EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: type == 'lecture' ? Theme.of(ctx).colorScheme.surface : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.menu_book, size: 16, color: type == 'lecture' ? C.teal : C.text4), SizedBox(width: 6), Text('Лекция', style: TextStyle(fontWeight: FontWeight.w600, color: type == 'lecture' ? C.teal : C.text4))])))),
              Expanded(child: GestureDetector(onTap: () => setS(() => type = 'material'),
                child: Container(padding: EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: type == 'material' ? Theme.of(ctx).colorScheme.surface : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.description_outlined, size: 16, color: type == 'material' ? C.teal : C.text4), SizedBox(width: 6), Text('Материал', style: TextStyle(fontWeight: FontWeight.w600, color: type == 'material' ? C.teal : C.text4))])))),
            ])),
          SizedBox(height: 20),
          _fieldLabel2('ТЕМА ${type == 'lecture' ? 'ЛЕКЦИИ' : 'МАТЕРИАЛА'} *'),
          TextField(controller: tc, decoration: InputDecoration(hintText: 'Например: Введение в тему...')),
          SizedBox(height: 16),
          _fieldLabel2('СОДЕРЖАНИЕ ${type == 'lecture' ? 'ЛЕКЦИИ' : 'МАТЕРИАЛА'}'),
          TextField(controller: cc, decoration: InputDecoration(hintText: 'Текст лекции, ссылки на видео...'), maxLines: 4),
          SizedBox(height: 20),
          // File upload
          _fieldLabel2('ПРИКРЕПИТЬ ФАЙЛЫ'),
          GestureDetector(onTap: () async {
            final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
            if (result != null) setS(() => lectureFiles.addAll(result.files));
          }, child: Container(padding: EdgeInsets.all(20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: C.teal.withOpacity(0.3))),
            child: Column(children: [
              Icon(Icons.upload_outlined, size: 24, color: C.teal), SizedBox(height: 6),
              RichText(text: TextSpan(style: TextStyle(fontSize: 13, color: C.text4), children: [TextSpan(text: 'Нажмите или '), TextSpan(text: 'выберите файлы', style: TextStyle(fontWeight: FontWeight.w700, color: C.teal))])),
              Text('PDF, DOCX, PPT, изображения', style: TextStyle(fontSize: 10, color: C.text4)),
            ]))),
          if (lectureFiles.isNotEmpty) ...[SizedBox(height: 8),
            ...lectureFiles.map((f) => Container(margin: EdgeInsets.only(bottom: 4), padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: C.teal.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [Icon(Icons.description, size: 14, color: C.teal), SizedBox(width: 6), Expanded(child: Text(f.name, style: TextStyle(fontSize: 12, color: C.teal), overflow: TextOverflow.ellipsis)), GestureDetector(onTap: () => setS(() => lectureFiles.remove(f)), child: Icon(Icons.close, size: 14, color: C.text4))])))],
          SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text('Отмена'), style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)))),
            SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(icon: Icon(Icons.add, size: 16, color: Colors.white), label: Text('Опубликовать'),
              style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                if (tc.text.trim().isEmpty) return;
                final prefix = type == 'lecture' ? '[LECTURE][${widget.classId}]' : '[HW][${widget.classId}]';
                try {
                  final api = context.read<ApiService>();
                  final fileUrls = <String>[];
                  for (final pf in lectureFiles) {
                    if (pf.path != null) {
                      try {
                        final res = await api.uploadFile(pf.path!, pf.name);
                        final url = res['url'] ?? res['file_url'] ?? res['path'];
                        if (url != null) fileUrls.add(url.toString());
                      } catch (_) {}
                    }
                  }
                  await api.createPost('$prefix ${tc.text.trim()}', jsonEncode({
                    'content': cc.text,
                    if (fileUrls.isNotEmpty) 'files': fileUrls,
                  }));
                  Navigator.pop(ctx); _load(); showToast(context, 'Опубликовано');
                } catch (_) { showToast(context, 'Ошибка', error: true); }
              })),
          ]),
        ]))));
  }

  void _createPost(String type) => _showAddMenu();

  void _createAssignment() {
    final tc = TextEditingController(), dc = TextEditingController(), sc = TextEditingController(text: '100');
    DateTime? deadline;
    List<Map<String, dynamic>> criteria = [{'name': '', 'weight': 100, 'desc': ''}];
    List<PlatformFile> attachedFiles = [];
    List<PlatformFile> referenceFiles = [];

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(expand: false, initialChildSize: 0.9, maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(controller: scroll, padding: EdgeInsets.all(24), children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: C.teal.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.edit_note, color: C.teal, size: 22)),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Новое задание', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text('Заполните данные задания', style: TextStyle(fontSize: 12, color: C.text4)),
            ])),
            IconButton(icon: Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ]),
          SizedBox(height: 24),
          _fieldLabel2('НАЗВАНИЕ ЗАДАНИЯ *'),
          TextField(controller: tc, decoration: InputDecoration(hintText: 'Например: Контрольная работа по теме...')),
          SizedBox(height: 16),
          _fieldLabel2('ОПИСАНИЕ ЗАДАНИЯ'),
          TextField(controller: dc, decoration: InputDecoration(hintText: 'Подробное описание, требования...'), maxLines: 4),
          SizedBox(height: 16),
          _fieldLabel2('МАКС. БАЛЛ'),
          TextField(controller: sc, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: '100')),
          SizedBox(height: 16),
          _fieldLabel2('ДЕДЛАЙН'),
          GestureDetector(onTap: () async {
            final d = await showDatePicker(context: ctx, initialDate: DateTime.now().add(Duration(days: 7)), firstDate: DateTime.now(), lastDate: DateTime.now().add(Duration(days: 365)));
            if (d != null) {
              final t = await showTimePicker(context: ctx, initialTime: TimeOfDay(hour: 23, minute: 59));
              setS(() => deadline = DateTime(d.year, d.month, d.day, t?.hour ?? 23, t?.minute ?? 59));
            }
          }, child: Container(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Text(deadline != null ? '${deadline!.day.toString().padLeft(2, '0')}.${deadline!.month.toString().padLeft(2, '0')}.${deadline!.year} ${deadline!.hour.toString().padLeft(2, '0')}:${deadline!.minute.toString().padLeft(2, '0')}' : 'ДД.ММ.ГГГГ --:--', style: TextStyle(fontSize: 14, color: deadline != null ? null : C.text4)),
              Spacer(), Icon(Icons.calendar_today, size: 18, color: C.text4),
            ]))),
          SizedBox(height: 20),
          // File attachments
          Row(children: [
            Text('ПРИКРЕПЛЁННЫЕ ФАЙЛЫ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.teal, letterSpacing: 1)),
            Spacer(),
            GestureDetector(
              onTap: () async {
                final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
                if (result != null) setS(() => attachedFiles.addAll(result.files));
              },
              child: Text('+ Добавить', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.teal)),
            ),
          ]),
          SizedBox(height: 8),
          if (attachedFiles.isEmpty)
            Container(padding: EdgeInsets.all(14), decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [Icon(Icons.attach_file, size: 16, color: C.text4), SizedBox(width: 8), Text('Нет прикреплённых файлов', style: TextStyle(fontSize: 13, color: C.text4))]))
          else
            ...attachedFiles.map((f) => Container(margin: EdgeInsets.only(bottom: 6), padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: C.teal.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(Icons.insert_drive_file_outlined, size: 16, color: C.teal),
                SizedBox(width: 8),
                Expanded(child: Text(f.name, style: TextStyle(fontSize: 13, color: C.teal, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: () => setS(() => attachedFiles.removeWhere((x) => x.name == f.name)),
                  child: Icon(Icons.close, size: 14, color: C.text4)),
              ]))),
          SizedBox(height: 20),
          // Reference solution
          Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: C.teal.withOpacity(0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.teal.withOpacity(0.15))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 36, height: 36, decoration: BoxDecoration(color: C.teal.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.check_circle_outline, size: 18, color: C.teal)),
                SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Text('Эталонные решения', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)), Spacer(), Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: C.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text('ИИ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.teal)))]),
                  Text('ИИ сравнит работы учеников с эталоном', style: TextStyle(fontSize: 11, color: C.text4)),
                ])),
              ]),
              SizedBox(height: 12),
              GestureDetector(onTap: () async {
                final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
                if (result != null) setS(() => referenceFiles.addAll(result.files));
              },
              child: Container(padding: EdgeInsets.all(20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: C.teal.withOpacity(0.3))),
                child: Column(children: [
                  Icon(Icons.upload_outlined, size: 28, color: C.teal),
                  SizedBox(height: 6),
                  RichText(text: TextSpan(style: TextStyle(fontSize: 13, color: C.text4), children: [TextSpan(text: 'Нажмите или '), TextSpan(text: 'выберите файлы', style: TextStyle(fontWeight: FontWeight.w700, color: C.teal))])),
                  Text('PDF, DOCX, DOC, PPTX, XLSX, TXT, MD', style: TextStyle(fontSize: 10, color: C.text4)),
                ]))),
              if (referenceFiles.isNotEmpty) ...[
                SizedBox(height: 8),
                ...referenceFiles.map((f) => Container(margin: EdgeInsets.only(bottom: 4), padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: C.teal.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [Icon(Icons.description, size: 14, color: C.teal), SizedBox(width: 6), Expanded(child: Text(f.name, style: TextStyle(fontSize: 12, color: C.teal), overflow: TextOverflow.ellipsis)), GestureDetector(onTap: () => setS(() => referenceFiles.remove(f)), child: Icon(Icons.close, size: 14, color: C.text4))]))),
              ],
            ])),
          SizedBox(height: 20),
          // Criteria
          Row(children: [
            Text('КРИТЕРИИ ОЦЕНИВАНИЯ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.teal, letterSpacing: 1)),
            Spacer(),
            GestureDetector(onTap: () => setS(() => criteria.add({'name': '', 'weight': 0, 'desc': ''})),
              child: Text('+ Добавить', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.teal))),
          ]),
          SizedBox(height: 4),
          Text('Сумма весов должна быть равна макс. баллу (${sc.text}/${sc.text})', style: TextStyle(fontSize: 11, color: C.text4)),
          SizedBox(height: 12),
          ...List.generate(criteria.length, (i) {
            final nameC = TextEditingController(text: criteria[i]['name']);
            final weightC = TextEditingController(text: '${criteria[i]['weight']}');
            final descC = TextEditingController(text: criteria[i]['desc'] ?? '');
            return Container(margin: EdgeInsets.only(bottom: 10), padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                Row(children: [
                  Text('${i + 1}', style: TextStyle(fontSize: 12, color: C.text4)),
                  SizedBox(width: 8),
                  Expanded(child: TextField(controller: nameC, decoration: InputDecoration(hintText: 'Название критерия', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)), onChanged: (v) => criteria[i]['name'] = v)),
                  SizedBox(width: 8),
                  SizedBox(width: 60, child: TextField(controller: weightC, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: InputDecoration(contentPadding: EdgeInsets.symmetric(vertical: 10)), onChanged: (v) => criteria[i]['weight'] = int.tryParse(v) ?? 0)),
                  SizedBox(width: 4),
                  GestureDetector(onTap: () { if (criteria.length > 1) setS(() => criteria.removeAt(i)); }, child: Icon(Icons.close, size: 16, color: C.red)),
                ]),
                SizedBox(height: 6),
                TextField(controller: descC, decoration: InputDecoration(hintText: 'Описание (необязательно)', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)), onChanged: (v) => criteria[i]['desc'] = v),
              ]));
          }),
          SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text('Отмена'), style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)))),
            SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(icon: Icon(Icons.add, size: 16, color: Colors.white), label: Text('Создать задание'),
              style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                if (tc.text.trim().isEmpty) return;
                try {
                  final api = context.read<ApiService>();
                  // Upload attached files
                  final fileUrls = <String>[];
                  for (final pf in attachedFiles) {
                    if (pf.path != null) {
                      try {
                        final res = await api.uploadFile(pf.path!, pf.name);
                        final url = res['url'] ?? res['file_url'] ?? res['path'];
                        if (url != null) fileUrls.add(url.toString());
                      } catch (_) {}
                    }
                  }
                  await api.createAssignment({
                    'class_id': widget.classId, 'title': tc.text.trim(), 'description': dc.text.trim(),
                    'max_score': int.tryParse(sc.text) ?? 100,
                    'criteria': criteria.where((c) => c['name'].toString().isNotEmpty).map((c) => {'name': c['name'], 'weight': c['weight'], 'description': c['desc']}).toList(),
                    if (deadline != null) 'deadline': deadline!.toIso8601String(),
                    if (fileUrls.isNotEmpty) 'file_urls': fileUrls,
                  });
                  Navigator.pop(ctx); _loadAssignments(); showToast(context, 'Задание создано');
                } catch (_) { showToast(context, 'Ошибка', error: true); }
              })),
          ]),
          SizedBox(height: 24),
        ]))));
  }

  Widget _fieldLabel2(String s) => Padding(padding: EdgeInsets.only(bottom: 8), child: Text(s, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.teal, letterSpacing: 1)));

  void _editClass() {
    final meta = _meta;
    final tc = TextEditingController(text: _title), dc = TextEditingController(text: meta['description'] ?? ''), tn = TextEditingController(text: meta['teacher_name'] ?? '');
    String? newCoverBase64 = meta['cover_image'];


    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(expand: false, initialChildSize: 0.85, maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(controller: scroll, padding: EdgeInsets.all(24), children: [
          // Header
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: C.teal.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.edit_outlined, color: C.teal, size: 22)),
            SizedBox(width: 12),
            Expanded(child: Text('Редактировать класс', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            IconButton(icon: Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ]),
          SizedBox(height: 24),
          // Cover image
          _fieldLabel2('ОБЛОЖКА КЛАССА'),
          GestureDetector(
            onTap: () async {
              final picker = ImagePicker();
              final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1200);
              if (img == null) return;
              final bytes = await img.readAsBytes();
              final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
              setS(() { newCoverBase64 = b64; });
            },
            child: Container(height: 150, decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: C.teal.withOpacity(0.3), width: 1.5)),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                if (newCoverBase64 != null && newCoverBase64!.startsWith('data:'))
                  Builder(builder: (_) { try { return Image.memory(base64Decode(newCoverBase64!.split(',').last), fit: BoxFit.cover); } catch (_) { return Container(color: C.teal.withOpacity(0.1)); } })
                else if (newCoverBase64 != null)
                  Image.network(newCoverBase64!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF006475), C.teal]))))
                else
                  Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF006475), C.teal], begin: Alignment.topLeft, end: Alignment.bottomRight))),
                // Overlay
                Container(color: Colors.black.withOpacity(0.3),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_photo_alternate_outlined, color: Colors.white, size: 32),
                    SizedBox(height: 6),
                    Text(newCoverBase64 != null ? 'Нажмите для замены' : 'Выбрать обложку', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  ])),
              ])),
          ),
          if (newCoverBase64 != null) ...[
            SizedBox(height: 8),
            GestureDetector(onTap: () => setS(() => newCoverBase64 = null),
              child: Row(children: [Icon(Icons.close, size: 14, color: C.red), SizedBox(width: 4), Text('Убрать обложку', style: TextStyle(fontSize: 12, color: C.red))])),
          ],
          SizedBox(height: 20),
          _fieldLabel2('НАЗВАНИЕ *'),
          TextField(controller: tc, decoration: InputDecoration(hintText: 'Название класса')),
          SizedBox(height: 16),
          _fieldLabel2('ОПИСАНИЕ'),
          TextField(controller: dc, decoration: InputDecoration(hintText: 'Описание класса'), maxLines: 3),
          SizedBox(height: 16),
          _fieldLabel2('ИМЯ УЧИТЕЛЯ'),
          TextField(controller: tn, decoration: InputDecoration(hintText: 'Отображаемое имя учителя')),
          SizedBox(height: 28),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text('Отмена'), style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)))),
            SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                try {
                  final post = _posts.firstWhere((p) => p['id'] == widget.classId, orElse: () => null);
                  if (post == null) return;
                  var body = <String, dynamic>{}; try { body = jsonDecode(post['body']); } catch (_) {}
                  body['type'] = 'class';
                  body['description'] = dc.text.trim();
                  body['teacher_name'] = tn.text.trim();
                  if (newCoverBase64 != null) body['cover_image'] = newCoverBase64;
                  else body.remove('cover_image');
                  await context.read<ApiService>().updatePost(widget.classId, tc.text.trim(), jsonEncode(body));
                  Navigator.pop(ctx); _load(); showToast(context, 'Класс обновлён');
                } catch (_) { showToast(context, 'Ошибка', error: true); }
              },
              child: Text('Сохранить'),
            )),
          ]),
          SizedBox(height: 24),
        ]))));
  }

  @override void dispose() { _tabCtrl.dispose(); super.dispose(); }
}

// ── AI Chat widget ──
class _AiChat extends StatefulWidget {
  final int classId; final String className;
  const _AiChat({required this.classId, required this.className});
  @override State<_AiChat> createState() => _AiChatState();
}
class _AiChatState extends State<_AiChat> {
  final _ctrl = TextEditingController(), _scroll = ScrollController();
  final List<Map<String, String>> _msgs = [];
  bool _loading = false;

  final _tips = ['Объясни материал', 'Ключевые понятия', 'Помощь с заданием', 'Частые ошибки'];

  void _send([String? override]) async {
    final text = override ?? _ctrl.text.trim(); if (text.isEmpty || _loading) return;
    setState(() { _msgs.add({'role': 'user', 'text': text}); _loading = true; }); _ctrl.clear();
    Future.delayed(Duration(milliseconds: 100), () { if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Duration(milliseconds: 200), curve: Curves.easeOut); });
    try {
      final api = context.read<ApiService>();
      final apiMsgs = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'Ты AI-ассистент курса "${widget.className}". Отвечай на русском.'},
        ..._msgs.map((m) => {'role': m['role']!, 'content': m['text']!}),
      ];
      final data = await api.aiChat(apiMsgs, classId: widget.classId);
      setState(() => _msgs.add({'role': 'assistant', 'text': data['content'] ?? 'Нет ответа'}));
    } catch (_) { setState(() => _msgs.add({'role': 'assistant', 'text': 'Ошибка соединения'})); }
    if (mounted) setState(() => _loading = false);
  }

  @override Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Column(children: [
      Expanded(child: _msgs.isEmpty
        ? Center(child: SingleChildScrollView(padding: EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 70, height: 70, decoration: BoxDecoration(color: C.teal.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.bolt, color: C.teal, size: 34)),
            SizedBox(height: 16),
            Text('Готов помочь!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            SizedBox(height: 6),
            Text('Спрашивайте по материалам курса', style: TextStyle(fontSize: 13, color: C.teal)),
            SizedBox(height: 20),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: _tips.map((t) => GestureDetector(
              onTap: () => _send(t),
              child: Container(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: adaptiveBorder(context))),
                child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500))))).toList()),
          ])))
        : ListView.builder(controller: _scroll, padding: EdgeInsets.fromLTRB(14, 12, 14, 8), itemCount: _msgs.length + (_loading ? 1 : 0), itemBuilder: (ctx, i) {
            if (i == _msgs.length) return Padding(padding: EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 28, height: 28, decoration: BoxDecoration(color: C.teal.withOpacity(0.12), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.auto_awesome, size: 14, color: C.teal)),
              SizedBox(width: 10),
              Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(14)),
                child: SizedBox(width: 40, height: 16, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: C.teal)))),
            ]));
            final m = _msgs[i]; final isU = m['role'] == 'user';
            if (isU) return Padding(padding: EdgeInsets.only(bottom: 14), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Flexible(child: Container(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(gradient: LinearGradient(colors: [C.teal, C.tealDk]), borderRadius: BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(4)),
                  boxShadow: [BoxShadow(color: C.teal.withOpacity(0.2), blurRadius: 10, offset: Offset(0, 3))]),
                child: Text(m['text'] ?? '', style: TextStyle(fontSize: 14, color: Colors.white, height: 1.5))))]));
            return Padding(padding: EdgeInsets.only(bottom: 14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 28, height: 28, margin: EdgeInsets.only(top: 2), decoration: BoxDecoration(color: C.teal.withOpacity(0.12), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.auto_awesome, size: 14, color: C.teal)),
              SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.teal)),
                SizedBox(height: 3),
                SelectableText(m['text'] ?? '', style: TextStyle(fontSize: 14, height: 1.6)),
              ])),
            ]));
          })),
      // Input
      Container(padding: EdgeInsets.fromLTRB(12, 8, 12, 4), decoration: BoxDecoration(color: surface),
        child: Row(children: [
          Expanded(child: Container(decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(22)),
            child: TextField(controller: _ctrl, decoration: InputDecoration(hintText: 'Спросите...', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10)), onSubmitted: (_) => _send(), maxLines: 3, minLines: 1))),
          SizedBox(width: 8),
          GestureDetector(onTap: _send, child: Container(width: 44, height: 44,
            decoration: BoxDecoration(gradient: LinearGradient(colors: [C.teal, C.tealDk]), borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: C.teal.withOpacity(0.3), blurRadius: 8, offset: Offset(0, 3))]),
            child: Icon(Icons.send_rounded, color: Colors.white, size: 20))),
        ])),
    ]);
  }
}
