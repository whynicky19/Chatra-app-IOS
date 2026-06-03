import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';

class ClassDetailScreen extends StatefulWidget {
  final int classId;
  final int initialTab;
  const ClassDetailScreen({super.key, required this.classId, this.initialTab = 0});
  @override State<ClassDetailScreen> createState() => _ClassDetailState();
}

class _ClassDetailState extends State<ClassDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<dynamic> _posts = [];
  List<dynamic> _assignments = [];
  List<dynamic> _mySubs = [];
  Map<String, dynamic> _rating = {};
  Map<String, String> _fileTexts = {};
  bool _loading = true, _loadingAsg = false;
  Set<int> _expandedCriteria = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this, initialIndex: widget.initialTab);
    _tabCtrl.addListener(() { if (_tabCtrl.index == 2 && _assignments.isEmpty) _loadAssignments(); });
    _load();
    if (widget.initialTab == 2) _loadAssignments();
  }

  Future<void> _load() async {
    if (!mounted) return; setState(() => _loading = true);
    final api = context.read<ApiService>();
    try { _posts = await api.getPosts(); } catch (_) {}
    if (!context.read<AuthProvider>().isTeacher) {
      try { _rating = await api.getMyRating(classId: widget.classId); } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
    _loadFileTexts();
  }

  Future<void> _loadFileTexts() async {
    if (!mounted) return;
    final api = context.read<ApiService>();
    final result = <String, String>{};
    for (final p in [..._lectures, ..._materials]) {
      List<dynamic> files = [];
      try {
        final b = jsonDecode(p['body'] ?? '');
        if (b['files'] is List) files = b['files'] as List;
      } catch (_) {}
      for (final f in files) {
        final url = _fixFileUrl(f.toString());
        final ext = url.split('?').first.split('.').last.toLowerCase();
        if (['txt', 'md'].contains(ext)) {
          try {
            final text = await api.fetchFileText(url);
            if (text.isNotEmpty) result[url] = text;
          } catch (_) {}
        }
      }
    }
    if (mounted) setState(() => _fileTexts = result);
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
    final l = context.watch<L10n>();
    final auth = context.watch<AuthProvider>();
    final meta = _meta;
    final coverImg = meta['cover_image'];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = Theme.of(context).colorScheme.surface;

    if (_loading) return Scaffold(body: Center(child: CircularProgressIndicator(color: C.teal)));

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverAppBar(
            expandedHeight: 220, pinned: true, stretch: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            leading: IconButton(
              icon: Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.arrow_back, color: Colors.white, size: 20)),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (auth.isTeacher) IconButton(
                icon: Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.edit, color: Colors.white70, size: 18)),
                onPressed: () => _editClass(),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              stretchModes: [StretchMode.zoomBackground],
              titlePadding: EdgeInsets.zero,
              background: Stack(fit: StackFit.expand, children: [
                Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF006475), C.teal], begin: Alignment.topLeft, end: Alignment.bottomRight))),
                if (coverImg != null && !coverImg.toString().startsWith('data:'))
                  Image.network(coverImg, fit: BoxFit.cover, alignment: Alignment.topCenter,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                if (coverImg != null && coverImg.toString().startsWith('data:'))
                  Builder(builder: (_) { try { return Image.memory(base64Decode(coverImg.toString().split(',').last), fit: BoxFit.cover, alignment: Alignment.topCenter); } catch (_) { return const SizedBox.shrink(); } }),
                Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0.0, 0.4, 1.0], colors: [Colors.black38, Colors.transparent, Colors.black54]))),
                Positioned(bottom: 16, left: 16, right: 16, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 6)]), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (meta['description'] != null && meta['description'].toString().isNotEmpty) ...[
                    SizedBox(height: 4),
                    Text(meta['description'], style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                  if (auth.isTeacher) ...[
                    SizedBox(height: 8),
                    GestureDetector(onTap: () { Clipboard.setData(ClipboardData(text: _code(widget.classId))); showToast(context, l.t('code_copied')); },
                      child: Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: adaptiveTealLt(context).withOpacity(0.9), borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.copy, size: 14, color: C.teal), SizedBox(width: 6), Text('${l.t('class_code')}: ', style: TextStyle(fontSize: 13, color: C.teal)), Text(_code(widget.classId), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: C.teal, letterSpacing: 2))]))),
                  ],
                ])),
              ]),
            ),
          ),
        ],
        body: Column(children: [
          Container(
            decoration: BoxDecoration(
              color: surfaceColor,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.18 : 0.05), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: Column(children: [
              TabBar(
                controller: _tabCtrl,
                labelColor: C.teal,
                unselectedLabelColor: C.text4,
                indicatorColor: C.teal,
                indicatorWeight: 2.5,
                indicatorSize: TabBarIndicatorSize.label,
                labelPadding: EdgeInsets.symmetric(horizontal: 12),
                labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.2),
                unselectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                tabs: [
                  Tab(text: '${l.t('lectures')} (${_lectures.length})'),
                  Tab(text: l.t('materials')),
                  Tab(text: l.t('assignments')),
                  Tab(text: l.t('ai_chat')),
                ],
              ),
              if (auth.isTeacher) AnimatedBuilder(animation: _tabCtrl, builder: (ctx, _) {
                if (_tabCtrl.index == 3) return SizedBox.shrink();
                return Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Row(children: [
                    Expanded(child: GestureDetector(
                      onTap: () => _createAssignment(),
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: adaptiveSurface2(context),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: C.teal.withOpacity(0.28)),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.assignment_add, size: 15, color: C.teal),
                          SizedBox(width: 6),
                          Text(l.t('assignment'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.teal)),
                        ]),
                      ),
                    )),
                    SizedBox(width: 10),
                    Expanded(child: GestureDetector(
                      onTap: () => _showAddMenu(),
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [C.teal, C.tealDk]),
                          borderRadius: BorderRadius.circular(13),
                          boxShadow: tealGlow(opacity: 0.28),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_rounded, size: 16, color: Colors.white),
                          SizedBox(width: 6),
                          Text(l.t('add'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                        ]),
                      ),
                    )),
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
    final l = context.read<L10n>();
    final surface = Theme.of(context).colorScheme.surface;
    final isTeacher = context.read<AuthProvider>().isTeacher;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLecture = type == 'lecture';
    final accentColor = isLecture ? C.teal : const Color(0xFF6366F1);

    if (posts.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80,
        decoration: BoxDecoration(gradient: RadialGradient(colors: [accentColor.withOpacity(0.18), accentColor.withOpacity(0.04)]), shape: BoxShape.circle),
        child: Icon(isLecture ? Icons.menu_book_rounded : Icons.inventory_2_outlined, size: 36, color: accentColor)),
      SizedBox(height: 18),
      Text(isLecture ? l.t('no_lectures') : l.t('no_materials'),
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: adaptiveText1(context))),
      SizedBox(height: 6),
      Text(isTeacher ? 'Добавьте первый материал' : 'Здесь появятся материалы курса',
        style: TextStyle(fontSize: 13, color: C.text4)),
    ]));

    return ListView.builder(padding: EdgeInsets.fromLTRB(14, 14, 14, 90), itemCount: posts.length, itemBuilder: (ctx, i) {
      final p = posts[i];
      final files = _extractFiles(p);
      final body = _preview(p);
      final num = posts.length - i;

      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: Duration(milliseconds: 260 + i * 55),
        curve: Curves.easeOutCubic,
        builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: child)),
        child: GestureDetector(
          onTap: () => _showPost(p, type, num),
          child: Container(
            margin: EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(20), boxShadow: cardShadow(isDark)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: EdgeInsets.fromLTRB(16, 16, 14, 14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Icon with number
                Container(width: 54, height: 54,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accentColor.withOpacity(0.18)),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(isLecture ? Icons.menu_book_rounded : Icons.inventory_2_outlined, color: accentColor, size: 20),
                    SizedBox(height: 2),
                    Text('$num', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: accentColor, height: 1)),
                  ])),
                SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: accentColor.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                    child: Text('${isLecture ? 'ЛЕКЦИЯ' : 'МАТЕРИАЛ'} $num',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: accentColor, letterSpacing: 0.6)),
                  ),
                  SizedBox(height: 6),
                  Text(_clean(p['title'] ?? ''),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.25, color: adaptiveText1(context)),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (body.isNotEmpty) Padding(padding: EdgeInsets.only(top: 5),
                    child: Text(body, style: TextStyle(fontSize: 13, color: C.text4, height: 1.45), maxLines: 2, overflow: TextOverflow.ellipsis)),
                ])),
                if (isTeacher) Column(mainAxisSize: MainAxisSize.min, children: [
                  _iconBtn(Icons.edit_outlined, () => _editPost(p)),
                  SizedBox(height: 4),
                  _iconBtn(Icons.delete_outline, () async { try { await context.read<ApiService>().deletePost(p['id']); _load(); } catch (_) {} }),
                ]),
              ])),
              // Footer
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: adaptiveSurface2(context).withOpacity(0.55),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                ),
                child: Row(children: [
                  Icon(Icons.access_time_rounded, size: 12, color: C.text4),
                  SizedBox(width: 4),
                  Text(_fmtDate(p['created_at'] ?? ''), style: TextStyle(fontSize: 12, color: C.text4)),
                  if (files.isNotEmpty) ...[
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: accentColor.withOpacity(0.10), borderRadius: BorderRadius.circular(6)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.attach_file_rounded, size: 10, color: accentColor),
                        SizedBox(width: 3),
                        Text('${files.length}', style: TextStyle(fontSize: 11, color: accentColor, fontWeight: FontWeight.w700)),
                      ])),
                  ],
                  Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: accentColor.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(l.t('open'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accentColor)),
                      SizedBox(width: 3),
                      Icon(Icons.arrow_forward_rounded, size: 12, color: accentColor),
                    ]),
                  ),
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
    // Preserve existing files from the body
    final Map<String, dynamic> existingBody = (() { try { return jsonDecode(p['body']) as Map<String, dynamic>; } catch (_) { return <String, dynamic>{}; } })();
    final List<dynamic> existingFiles = existingBody['files'] is List ? existingBody['files'] as List : [];

    final List<dynamic> editFiles = List<dynamic>.from(existingFiles);

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Padding(padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2))),
            SizedBox(height: 20), Text('Редактировать', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            SizedBox(height: 16), TextField(controller: tc, decoration: InputDecoration(labelText: 'Заголовок')),
            SizedBox(height: 12), TextField(controller: cc, decoration: InputDecoration(labelText: 'Содержание'), maxLines: 5),
            if (editFiles.isNotEmpty) ...[
              SizedBox(height: 16),
              Align(alignment: Alignment.centerLeft, child: Text('Прикреплённые файлы', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.text3))),
              SizedBox(height: 8),
              ...editFiles.map((f) {
                final name = Uri.parse(f.toString()).pathSegments.last;
                return Container(
                  margin: EdgeInsets.only(bottom: 6),
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: C.teal.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Icon(Icons.insert_drive_file_outlined, size: 14, color: C.teal),
                    SizedBox(width: 6),
                    Expanded(child: Text(name, style: TextStyle(fontSize: 12, color: C.teal), overflow: TextOverflow.ellipsis)),
                    GestureDetector(onTap: () => setS(() => editFiles.remove(f)), child: Icon(Icons.close, size: 14, color: C.text4)),
                  ]),
                );
              }),
            ],
            SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
                if (result != null) {
                  final api = context.read<ApiService>();
                  for (final pf in result.files) {
                    if (pf.path != null) {
                      try {
                        final res = await api.uploadFile(pf.path!, pf.name);
                        final url = res['url'] ?? res['file_url'] ?? res['path'];
                        if (url != null) setS(() => editFiles.add(url.toString()));
                      } catch (_) {}
                    }
                  }
                }
              },
              child: Container(padding: EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.teal.withOpacity(0.3))),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.attach_file, size: 16, color: C.teal), SizedBox(width: 6), Text('Прикрепить файлы', style: TextStyle(fontSize: 13, color: C.teal, fontWeight: FontWeight.w600))])),
            ),
            SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text('Отмена'))),
              SizedBox(width: 12),
              Expanded(child: ElevatedButton(onPressed: () async {
                try {
                  final prefix = (p['title'] ?? '').startsWith('[LECTURE]') ? '[LECTURE][${widget.classId}] ' : '[HW][${widget.classId}] ';
                  await context.read<ApiService>().updatePost(p['id'], '$prefix${tc.text.trim()}', jsonEncode({
                    'content': cc.text,
                    if (editFiles.isNotEmpty) 'files': editFiles,
                  }));
                  Navigator.pop(ctx); _load(); showToast(context, 'Сохранено');
                } catch (_) { showToast(context, 'Ошибка', error: true); }
              }, child: Text('Сохранить'))),
            ]),
          ])));
      }));
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

  /// Fix localhost/127.0.0.1 URLs and relative paths to use the actual API base URL
  String _fixFileUrl(String url) {
    if (url.isEmpty) return url;
    final api = context.read<ApiService>();
    final base = api.baseUrl; // e.g. http://10.0.2.2:8000
    var fixed = url
        .replaceAll(RegExp(r'https?://localhost:\d+'), base)
        .replaceAll(RegExp(r'https?://127\.0\.0\.1:\d+'), base);
    // Handle relative paths like /uploads/file.pdf
    if (!fixed.startsWith('http') && !fixed.startsWith('ws')) {
      fixed = '$base${fixed.startsWith('/') ? '' : '/'}$fixed';
    }
    return fixed;
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
    final l = context.read<L10n>();
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
              Text(l.t('your_rating'), style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
              SizedBox(height: 8),
              RichText(text: TextSpan(children: [
                TextSpan(text: '$avg', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, height: 1)),
                TextSpan(text: ' /100', style: TextStyle(color: Colors.white60, fontSize: 14, fontWeight: FontWeight.w600)),
              ])),
              SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
                value: avg / 100, backgroundColor: Colors.white24, color: Colors.white, minHeight: 4)),
              SizedBox(height: 4),
              Text('${l.t('performance')}: $pct%', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
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
          child: Row(children: [Icon(Icons.sort_rounded, size: 14, color: C.text4), SizedBox(width: 4), Text(l.t('sort_deadline'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.text4))])),
      ]),
      SizedBox(height: 12),
      if (_assignments.isEmpty) Container(padding: EdgeInsets.symmetric(vertical: 52), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 80, height: 80,
          decoration: BoxDecoration(gradient: RadialGradient(colors: [C.teal.withOpacity(0.16), C.teal.withOpacity(0.04)]), shape: BoxShape.circle),
          child: Icon(Icons.assignment_outlined, size: 36, color: C.teal)),
        SizedBox(height: 18),
        Text(l.t('no_assignments'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: adaptiveText1(context))),
        SizedBox(height: 6),
        Text(auth.isTeacher ? 'Создайте первое задание' : 'Заданий пока нет',
          style: TextStyle(fontSize: 13, color: C.text4)),
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
        String statusText = isGraded ? l.t('graded') : isSubmitted ? l.t('submitted') : isLate ? l.t('overdue') : l.t('new_status');
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
                boxShadow: cardShadow(isDark),
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
                        Text('${a['max_score'] ?? 100} ${l.t('pts')}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.teal)),
                      ]),
                      if (grade != null) Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_circle_rounded, size: 12, color: C.green), SizedBox(width: 3),
                        Text('${grade['score']}/${a['max_score']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: C.green)),
                      ]),
                    ]),
                  ])),
                ])),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: adaptiveSurface2(context).withOpacity(0.45),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
                  ),
                  child: Row(children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: statusColor.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(statusIcon, size: 12, color: statusColor),
                        SizedBox(width: 4),
                        Text(statusText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                      ]),
                    ),
                    Spacer(),
                    Row(children: [
                      Text('Открыть', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.teal)),
                      SizedBox(width: 3),
                      Icon(Icons.arrow_forward_rounded, size: 13, color: C.teal),
                    ]),
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
  String get _lectureContextForAI {
    final all = [..._lectures, ..._materials].take(8);
    final parts = <String>[];
    for (final p in all) {
      final title = _clean(p['title'] ?? '');
      String content = '';
      List<dynamic> files = [];
      try {
        final b = jsonDecode(p['body']);
        content = (b['content'] ?? b['description'] ?? '').toString();
        if (b['files'] is List) files = b['files'] as List;
      } catch (_) { content = p['body'] ?? ''; }
      content = content.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
      if (content.length > 1500) content = content.substring(0, 1500);
      final sb = StringBuffer();
      if (title.isNotEmpty) sb.write('### $title\n');
      if (content.isNotEmpty) sb.write(content);
      if (files.isNotEmpty) {
        for (final f in files) {
          final url = _fixFileUrl(f.toString());
          final name = (() { try { return Uri.parse(url).pathSegments.last; } catch (_) { return url; } })();
          final ext = url.split('?').first.split('.').last.toLowerCase();
          if (_fileTexts.containsKey(url)) {
            var text = _fileTexts[url]!;
            if (text.length > 2000) text = '${text.substring(0, 2000)}...';
            sb.write('\n[Файл "$name"]\n$text');
          } else if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
            sb.write('\n[Изображение: $name]');
          } else {
            sb.write('\n[Прикреплённый файл: $name]');
          }
        }
      }
      if (sb.isNotEmpty) parts.add(sb.toString());
    }
    return parts.join('\n\n');
  }

  List<String> get _lectureImageUrls {
    final all = [..._lectures, ..._materials];
    final urls = <String>[];
    for (final p in all) {
      for (final f in _extractFiles(p)) {
        final ext = f.split('?').first.split('.').last.toLowerCase();
        if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) urls.add(f);
        if (urls.length >= 3) return urls;
      }
    }
    return urls;
  }

  Widget _aiTab() => NotificationListener<ScrollNotification>(
    onNotification: (_) => true,
    child: _AiChat(classId: widget.classId, className: _title, lectureContext: _lectureContextForAI, lectureImageUrls: _lectureImageUrls),
  );

  // ── Show post detail ──
  void _showPost(dynamic p, String type, int num) {
    String content = '';
    try { final b = jsonDecode(p['body']); content = b['content'] ?? b['description'] ?? ''; }
    catch (_) { content = p['body'] ?? ''; }
    final files    = _extractFiles(p);
    final cleanText = _cleanContent(content);
    final isLecture = type == 'lecture';
    final accent    = isLecture ? C.teal : const Color(0xFF6366F1);
    final isDark    = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.96,
        minChildSize: 0.4,
        builder: (ctx, sc) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            // ── Colored header strip ──────────────────────
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isLecture
                      ? [const Color(0xFF006475), C.teal]
                      : [const Color(0xFF3730A3), const Color(0xFF6366F1)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Handle + close row
                Row(children: [
                  Expanded(child: Center(child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.35), borderRadius: BorderRadius.circular(2)),
                  ))),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.18), shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                // Type badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.22), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '${isLecture ? 'ЛЕКЦИЯ' : 'МАТЕРИАЛ'} $num',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1.0),
                  ),
                ),
                const SizedBox(height: 10),
                // Title
                Text(
                  _clean(p['title'] ?? ''),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, height: 1.25, letterSpacing: -0.3),
                  maxLines: 3, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                // Meta row
                Row(children: [
                  Icon(Icons.calendar_today_outlined, size: 12, color: Colors.white60),
                  const SizedBox(width: 5),
                  Text(_fmtDate(p['created_at'] ?? ''), style: const TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w500)),
                  if (files.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Container(width: 4, height: 4, decoration: BoxDecoration(color: Colors.white30, shape: BoxShape.circle)),
                    const SizedBox(width: 12),
                    Icon(Icons.attach_file_rounded, size: 12, color: Colors.white60),
                    const SizedBox(width: 4),
                    Text('${files.length} ${files.length == 1 ? 'файл' : 'файла'}', style: const TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w500)),
                  ],
                ]),
              ]),
            ),

            // ── Scrollable content ────────────────────────
            Expanded(child: ListView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
              children: [
                // Content text
                if (cleanText.isNotEmpty) ...[
                  Row(children: [
                    Container(width: 3, height: 18, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 10),
                    Text('Содержание', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: accent, letterSpacing: 0.3)),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? C.darkSurface2 : C.bg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accent.withOpacity(0.1)),
                    ),
                    child: Text(cleanText, style: const TextStyle(fontSize: 15, height: 1.75, letterSpacing: 0.1)),
                  ),
                  const SizedBox(height: 24),
                ],

                // Files
                if (files.isNotEmpty) ...[
                  Row(children: [
                    Container(width: 3, height: 18, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 10),
                    Text('Прикреплённые файлы', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: accent, letterSpacing: 0.3)),
                  ]),
                  const SizedBox(height: 12),
                  ...files.asMap().entries.map((entry) {
                    final i = entry.key; final f = entry.value;
                    final name = Uri.parse(f).pathSegments.last;
                    final ext  = name.split('.').last.toLowerCase();

                    // File type config
                    final fileConfig = _fileTypeConfig(ext);
                    final fileIcon  = fileConfig['icon'] as IconData;
                    final fileColor = fileConfig['color'] as Color;
                    final fileBg    = fileConfig['bg'] as Color;

                    return TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: Duration(milliseconds: 250 + i * 60),
                      curve: Curves.easeOutCubic,
                      builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 8*(1-t)), child: child)),
                      child: GestureDetector(
                        onTap: () async {
                          try { await launchUrl(Uri.parse(f), mode: LaunchMode.inAppBrowserView); } catch (_) {}
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? C.darkSurface2 : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: fileColor.withOpacity(0.18)),
                            boxShadow: [BoxShadow(color: fileColor.withOpacity(isDark ? 0.04 : 0.07), blurRadius: 10, offset: const Offset(0, 3))],
                          ),
                          child: Row(children: [
                            // File type badge
                            Container(
                              width: 46, height: 46,
                              decoration: BoxDecoration(color: fileBg, borderRadius: BorderRadius.circular(12)),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(fileIcon, size: 20, color: fileColor),
                                const SizedBox(height: 1),
                                Text(ext.toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: fileColor, letterSpacing: 0.5)),
                              ]),
                            ),
                            const SizedBox(width: 13),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.2), overflow: TextOverflow.ellipsis, maxLines: 1),
                              const SizedBox(height: 3),
                              Text('Нажмите для открытия', style: TextStyle(fontSize: 11, color: C.text4)),
                            ])),
                            Container(
                              width: 34, height: 34,
                              decoration: BoxDecoration(color: fileColor.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
                              child: Icon(Icons.open_in_new_rounded, size: 16, color: fileColor),
                            ),
                          ]),
                        ),
                      ),
                    );
                  }),
                ],

                // Empty — no content and no files
                if (cleanText.isEmpty && files.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 64, height: 64,
                        decoration: BoxDecoration(color: accent.withOpacity(0.08), shape: BoxShape.circle),
                        child: Icon(isLecture ? Icons.menu_book_rounded : Icons.inventory_2_outlined, size: 30, color: accent)),
                      const SizedBox(height: 14),
                      const Text('Содержимое ещё не добавлено', style: TextStyle(fontSize: 14, color: C.text4, fontWeight: FontWeight.w500)),
                    ])),
                  ),
              ],
            )),
          ]),
        ),
      ),
    );
  }

  // Парсит URL файлов из одного поля (любого формата)
  List<String> _parseFileUrls(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((f) => _fixFileUrl(f.toString())).where((s) => s.isNotEmpty).toList();
    }
    if (raw is String && raw.isNotEmpty) {
      // JSON-строка вида '["url1","url2"]'
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((f) => _fixFileUrl(f.toString())).where((s) => s.isNotEmpty).toList();
        }
        if (decoded is String && decoded.isNotEmpty) return [_fixFileUrl(decoded)];
      } catch (_) {}
      // Одиночный URL
      if (raw.startsWith('http') || raw.startsWith('/')) return [_fixFileUrl(raw)];
    }
    return [];
  }

  // Извлекает все файлы задания — объединяет данные из ДВУХ объектов
  // (список /assignments/ и детали /assignments/{id} могут отличаться)
  List<String> _extractAssignmentFiles(dynamic listA, [dynamic detailA]) {
    final result = <String>{};
    // Берём из всех возможных полей обоих источников
    for (final src in [listA, if (detailA != null) detailA]) {
      if (src == null) continue;
      result.addAll(_parseFileUrls(src['file_urls']));
      result.addAll(_parseFileUrls(src['files']));
      result.addAll(_parseFileUrls(src['attachments']));
      if (src['file_url'] != null) result.add(_fixFileUrl(src['file_url'].toString()));
      // URL из описания (legacy)
      if (src['description'] != null) {
        result.addAll(_extractFilesFromText(src['description'].toString()));
      }
    }
    // debug: выводим что нашли
    debugPrint('[Files] listA file_urls=${listA?['file_urls']} detailA file_urls=${detailA?['file_urls']} result=$result');
    return result.where((s) => s.isNotEmpty).toList();
  }

  Map<String, dynamic> _fileTypeConfig(String ext) {
    switch (ext) {
      case 'pdf':
        return {'icon': Icons.picture_as_pdf_rounded, 'color': const Color(0xFFE53E3E), 'bg': const Color(0xFFFFF5F5)};
      case 'pptx': case 'ppt':
        return {'icon': Icons.slideshow_rounded,       'color': const Color(0xFFDD6B20), 'bg': const Color(0xFFFFFAF0)};
      case 'doc': case 'docx':
        return {'icon': Icons.description_rounded,    'color': const Color(0xFF2B6CB0), 'bg': const Color(0xFFEBF8FF)};
      case 'xlsx': case 'xls':
        return {'icon': Icons.table_chart_rounded,    'color': const Color(0xFF276749), 'bg': const Color(0xFFF0FFF4)};
      case 'txt': case 'md':
        return {'icon': Icons.text_snippet_rounded,   'color': const Color(0xFF553C9A), 'bg': const Color(0xFFFAF5FF)};
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp':
        return {'icon': Icons.image_rounded,          'color': const Color(0xFF0C4A6E), 'bg': const Color(0xFFE0F2FE)};
      case 'mp4': case 'mov': case 'avi':
        return {'icon': Icons.play_circle_rounded,    'color': const Color(0xFF6B21A8), 'bg': const Color(0xFFF5F3FF)};
      default:
        return {'icon': Icons.insert_drive_file_rounded, 'color': C.text4,             'bg': C.surface2};
    }
  }

  // ── Show assignment detail ──
  void _showAssignment(dynamic a, dynamic sub) {
    final tc = TextEditingController(); bool busy = false;
    final auth = context.read<AuthProvider>();
    final isTeacherOrAdmin = auth.isTeacher;
    List<dynamic> criteria = []; try { criteria = jsonDecode(a['criteria'] ?? '[]'); } catch (_) {}
    List<PlatformFile> pickedFiles = [];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final deadline = a['deadline'];
    final isLate = deadline != null && DateTime.tryParse(deadline)?.isBefore(DateTime.now()) == true && sub == null;
    final sheetStatusColor = sub?['status'] == 'graded' ? C.green
        : sub?['status'] == 'submitted' ? C.teal
        : isLate ? C.red : C.text4;
    final sheetStatusText = sub?['status'] == 'graded' ? 'Проверено'
        : sub?['status'] == 'submitted' ? 'Сдано'
        : isLate ? 'Просрочено' : 'Новое';

    // Future для полных данных задания — создаём один раз вне builder
    final assignmentFuture = context.read<ApiService>()
        .getAssignment((a['id'] as num).toInt());

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return DraggableScrollableSheet(
        expand: false, initialChildSize: 0.88, maxChildSize: 0.97, minChildSize: 0.5,
        builder: (ctx, sc) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            // ── Clean teal header ──
            Container(
              decoration: BoxDecoration(
                color: isDark ? C.darkSurface : Colors.white,
                border: Border(bottom: BorderSide(color: adaptiveBorder(context), width: 1)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Handle + close row
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 16, 0),
                  child: Row(children: [
                    Expanded(child: Center(child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2)),
                    ))),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(width: 32, height: 32,
                        decoration: BoxDecoration(color: adaptiveSurface2(context), shape: BoxShape.circle),
                        child: Icon(Icons.close_rounded, color: C.text4, size: 16)),
                    ),
                  ]),
                ),
                // Status + type badges
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Row(children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: C.teal.withOpacity(0.10), borderRadius: BorderRadius.circular(7)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.assignment_outlined, size: 11, color: C.teal),
                        SizedBox(width: 4),
                        Text('ЗАДАНИЕ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: C.teal, letterSpacing: 0.6)),
                      ]),
                    ),
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: sheetStatusColor.withOpacity(0.10), borderRadius: BorderRadius.circular(7)),
                      child: Text(sheetStatusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sheetStatusColor)),
                    ),
                  ]),
                ),
                // Title
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Text(a['title'] ?? '',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, height: 1.2, letterSpacing: -0.3, color: adaptiveText1(context)),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                // Meta row
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 20, 16),
                  child: Row(children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: C.teal.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.star_rounded, size: 13, color: C.teal), SizedBox(width: 4),
                        Text('${a['max_score'] ?? 100} баллов', style: TextStyle(fontSize: 12, color: C.teal, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    if (deadline != null) ...[
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isLate ? C.red.withOpacity(0.08) : adaptiveSurface2(context),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.calendar_today_outlined, size: 12, color: isLate ? C.red : C.text4),
                          SizedBox(width: 4),
                          Text(_fmtDate(deadline), style: TextStyle(fontSize: 12, color: isLate ? C.red : C.text4, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ],
                  ]),
                ),
              ]),
            ),
            // ── Scrollable content ──
            Expanded(child: ListView(controller: sc, padding: EdgeInsets.fromLTRB(20, 20, 20, 24), children: [
        // Описание + файлы загружаем через FutureBuilder
        FutureBuilder<Map<String, dynamic>>(
          future: assignmentFuture,
          builder: (ctx, snap) {
            final detailA   = snap.data;
            final isLoading = snap.connectionState == ConnectionState.waiting;
            final hasError  = snap.hasError;

            // Описание из детального ответа, fallback на список
            final descText = _cleanContent(
              ((detailA?['description'] ?? a['description'])?.toString()) ?? '');

            // Файлы: объединяем из ОБОИХ источников
            final allFiles = _extractAssignmentFiles(a, detailA);

            // Видимый debug-блок (временно, пока разбираемся с API)
            final rawFromList   = a['file_urls'];
            final rawFromDetail = detailA?['file_urls'];
            final showDebug = !isLoading && allFiles.isEmpty &&
                (rawFromList != null || rawFromDetail != null || hasError);

            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Описание
              if (descText.isNotEmpty) ...[
                Row(children: [Container(width: 3, height: 16, decoration: BoxDecoration(color: C.teal, borderRadius: BorderRadius.circular(2))), SizedBox(width: 8), Text('Описание', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.teal))]),
                SizedBox(height: 10),
                Container(padding: EdgeInsets.all(14), decoration: BoxDecoration(color: isDark ? C.darkSurface2 : C.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.teal.withOpacity(0.10))),
                  child: Text(descText, style: TextStyle(fontSize: 14, height: 1.65))),
                SizedBox(height: 20),
              ],
              // Файлы
              if (isLoading) Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.teal)),
                  SizedBox(width: 10),
                  Text('Загрузка файлов...', style: TextStyle(fontSize: 13, color: C.text4)),
                ]),
              )
              else if (allFiles.isNotEmpty) ...[
                Row(children: [
                  Container(width: 3, height: 16, decoration: BoxDecoration(color: C.teal, borderRadius: BorderRadius.circular(2))),
                  SizedBox(width: 8),
                  Text('Прикреплённые файлы', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.teal, letterSpacing: 0.3)),
                ]),
                SizedBox(height: 10),
                ...allFiles.asMap().entries.map((entry) {
              final i = entry.key; final f = entry.value;
              final name = Uri.parse(f).pathSegments.last;
              final ext = name.split('.').last.toLowerCase();
              final fc = _fileTypeConfig(ext);
              final fileIcon = fc['icon'] as IconData;
              final fileColor = fc['color'] as Color;
              final fileBg = fc['bg'] as Color;
              return GestureDetector(
                onTap: () async { try { await launchUrl(Uri.parse(f), mode: LaunchMode.inAppBrowserView); } catch (_) {} },
                child: Container(
                  margin: EdgeInsets.only(bottom: 8),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? C.darkSurface2 : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: fileColor.withOpacity(0.2)),
                    boxShadow: [BoxShadow(color: fileColor.withOpacity(0.06), blurRadius: 8, offset: Offset(0, 2))],
                  ),
                  child: Row(children: [
                    Container(width: 42, height: 42, decoration: BoxDecoration(color: fileBg, borderRadius: BorderRadius.circular(11)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(fileIcon, size: 18, color: fileColor),
                        SizedBox(height: 1),
                        Text(ext.toUpperCase(), style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900, color: fileColor)),
                      ])),
                    SizedBox(width: 11),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                      Text('Нажмите для открытия', style: TextStyle(fontSize: 11, color: C.text4)),
                    ])),
                    Container(width: 32, height: 32, decoration: BoxDecoration(color: fileColor.withOpacity(0.1), borderRadius: BorderRadius.circular(9)),
                      child: Icon(Icons.open_in_new_rounded, size: 15, color: fileColor)),
                  ]),
                ),
              );
            }),
                SizedBox(height: 8),
              ],
              // Debug: показывает raw данные от API если файлы не нашлись
              if (showDebug) Container(
                margin: EdgeInsets.only(top: 8, bottom: 8),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withOpacity(0.3))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('DEBUG: file_urls', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.orange)),
                  SizedBox(height: 4),
                  Text('list: $rawFromList', style: TextStyle(fontSize: 10, color: C.text4)),
                  Text('detail: $rawFromDetail', style: TextStyle(fontSize: 10, color: C.text4)),
                  if (hasError) Text('error: ${snap.error}', style: TextStyle(fontSize: 10, color: C.red)),
                ]),
              ),
            ]);
          },
        ),
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
        if (sub != null && (sub['text_content'] != null || sub['file_urls'] != null)) ...[
          SizedBox(height: 16),
          Text('ВАШ ОТВЕТ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
          SizedBox(height: 6),
          if (sub['text_content'] != null && sub['text_content'].toString().isNotEmpty)
            Container(padding: EdgeInsets.all(12), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12)),
              child: Text(sub['text_content'], style: TextStyle(fontSize: 13, height: 1.6), maxLines: 5, overflow: TextOverflow.ellipsis)),
          ...(() {
            List<String> urls = [];
            final raw = sub['file_urls'];
            if (raw is String && raw.isNotEmpty) {
              try { urls = (jsonDecode(raw) as List).map((f) => _fixFileUrl(f.toString())).toList(); } catch (_) {}
            } else if (raw is List) {
              urls = raw.map((f) => _fixFileUrl(f.toString())).toList();
            }
            if (urls.isEmpty) return <Widget>[];
            return [
              SizedBox(height: 8),
              ...urls.map((url) {
                final name = Uri.parse(url).pathSegments.last;
                final ext = name.split('.').last.toLowerCase();
                final icon = ext == 'pdf' ? Icons.picture_as_pdf : ext == 'pptx' || ext == 'ppt' ? Icons.slideshow : ext == 'doc' || ext == 'docx' ? Icons.description : Icons.insert_drive_file;
                return GestureDetector(
                  onTap: () async { try { await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView); } catch (_) {} },
                  child: Container(margin: EdgeInsets.only(bottom: 6), padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(color: C.teal.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Icon(icon, size: 16, color: C.teal), SizedBox(width: 8),
                      Expanded(child: Text(name, style: TextStyle(fontSize: 13, color: C.teal, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                      Icon(Icons.open_in_new_rounded, size: 14, color: C.teal),
                    ])),
                );
              }),
            ];
          })(),
        ],
        // Retract button (students, submitted but not graded and no grade yet)
        if (!isTeacherOrAdmin && sub != null && sub['status'] != 'graded' && sub['grade'] == null) ...[
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
        // Teacher: edit / delete / view submissions
        if (isTeacherOrAdmin) ...[
          SizedBox(height: 20),
          Divider(height: 1, color: adaptiveBorder(context)),
          SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              icon: Icon(Icons.edit_outlined, size: 16),
              label: Text('Редактировать'),
              onPressed: () { Navigator.pop(ctx); _editAssignment(a); },
              style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 12)),
            )),
            SizedBox(width: 10),
            OutlinedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: Text('Удалить задание?', style: TextStyle(fontWeight: FontWeight.w800)),
                  content: Text('Это действие нельзя отменить', style: TextStyle(color: C.text4)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Отмена')),
                    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: C.red), onPressed: () => Navigator.pop(d, true), child: Text('Удалить')),
                  ],
                ));
                if (ok == true) {
                  try { await context.read<ApiService>().deleteAssignment(a['id']); _loadAssignments(); showToast(context, 'Задание удалено'); }
                  catch (_) { showToast(context, 'Ошибка', error: true); }
                }
              },
              style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12), side: BorderSide(color: C.red.withOpacity(0.5))),
              child: Icon(Icons.delete_outline_rounded, size: 18, color: C.red),
            ),
          ]),
          SizedBox(height: 10),
          SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(
            icon: Icon(Icons.list_alt, size: 18),
            label: Text('Просмотр работ'),
            onPressed: () => _viewSubs(a['id']),
            style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 12)),
          )),
        ],
        SizedBox(height: 24),
      ])),
          ]),
        ),
      );
      }),
    );
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
          bool grading = false;
          return StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(expand: false, initialChildSize: 0.85, maxChildSize: 0.95, builder: (ctx, sc) {
            // Detail view for selected student
            if (selectedSub != null) {
              final name = selectedSub['student_name'] ?? '#${selectedSub['student_id']}';
              final initials = name.length >= 2 ? '${name[0]}${name.split(' ').length > 1 ? name.split(' ').last[0] : name[1]}'.toUpperCase() : name[0].toUpperCase();
              final grade = selectedSub['grade'];
              final score = grade?['score'];
              final feedback = grade?['feedback'];
              final criteria = grade?['criteria'] as List<dynamic>? ?? [];
              // Collect submitted file URLs from file_urls field
              List<String> submittedFileUrls = [];
              final rawUrls = selectedSub['file_urls'];
              if (rawUrls is List) {
                submittedFileUrls = rawUrls.map((f) => _fixFileUrl(f.toString())).toList();
              } else if (rawUrls is String && rawUrls.isNotEmpty) {
                try { submittedFileUrls = (jsonDecode(rawUrls) as List).map((f) => _fixFileUrl(f.toString())).toList(); } catch (_) {}
              }
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
                // Attached text and files
                if (selectedSub['text_content'] != null || submittedFileUrls.isNotEmpty) ...[
                  SizedBox(height: 16),
                  Text('РАБОТА СТУДЕНТА', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                  SizedBox(height: 8),
                  if (selectedSub['text_content'] != null) Container(padding: EdgeInsets.all(12), margin: EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(color: C.teal.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                    child: Text(selectedSub['text_content'], style: TextStyle(fontSize: 13))),
                  ...submittedFileUrls.map((url) {
                    final name = Uri.parse(url).pathSegments.last;
                    final ext = name.split('.').last.toLowerCase();
                    final icon = ext == 'pdf' ? Icons.picture_as_pdf : ext == 'pptx' || ext == 'ppt' ? Icons.slideshow : ext == 'doc' || ext == 'docx' ? Icons.description : Icons.insert_drive_file;
                    return GestureDetector(
                      onTap: () async { try { await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView); } catch (_) {} },
                      child: Container(padding: EdgeInsets.all(12), margin: EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(color: C.teal.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          Icon(icon, size: 18, color: C.teal), SizedBox(width: 8),
                          Expanded(child: Text(name, style: TextStyle(fontSize: 13, color: C.teal), overflow: TextOverflow.ellipsis)),
                          Icon(Icons.open_in_new_rounded, size: 14, color: C.teal),
                        ])));
                  }),
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
                  SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
                    style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
                    onPressed: grading ? null : () async {
                      setS(() => grading = true);
                      try {
                        await context.read<ApiService>().aiGrade(selectedSub['id']);
                        final updated = await context.read<ApiService>().getSubmission(selectedSub['id']);
                        setS(() { selectedSub = updated; grading = false; });
                        showToast(context, 'Переоценено!');
                      } catch (e) {
                        setS(() => grading = false);
                        final msg = e.toString().contains('criteria') ? 'Нет критериев оценивания' : 'Ошибка оценки';
                        showToast(context, msg, error: true);
                      }
                    },
                    child: grading
                      ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                          SizedBox(width: 12),
                          Text('ИИ оценивает...', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ])
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.bolt, size: 18, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Перепроверить ИИ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ]),
                  )),
                ] else ...[
                  SizedBox(height: 20),
                  SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
                    style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
                    onPressed: grading ? null : () async {
                      setS(() => grading = true);
                      try {
                        await context.read<ApiService>().aiGrade(selectedSub['id']);
                        final updated = await context.read<ApiService>().getSubmission(selectedSub['id']);
                        setS(() { selectedSub = updated; grading = false; });
                        showToast(context, 'Оценено!');
                      } catch (e) {
                        setS(() => grading = false);
                        final msg = e.toString().contains('criteria') ? 'Нет критериев оценивания' : 'Ошибка оценки';
                        showToast(context, msg, error: true);
                      }
                    },
                    child: grading
                      ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                          SizedBox(width: 12),
                          Text('ИИ оценивает...', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ])
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.bolt, size: 18, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Оценить ИИ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ]),
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

                  // Upload attached files с явной обработкой ошибок
                  final fileUrls = <String>[];
                  for (final pf in [...attachedFiles, ...referenceFiles]) {
                    if (pf.path != null) {
                      try {
                        final res = await api.uploadFile(pf.path!, pf.name);
                        final url = res['url'] ?? res['file_url'] ?? res['path'];
                        if (url != null && url.toString().isNotEmpty) {
                          fileUrls.add(url.toString());
                          debugPrint('[Upload] OK: $url');
                        } else {
                          debugPrint('[Upload] No URL in response: $res');
                        }
                      } catch (e) {
                        debugPrint('[Upload] Error for ${pf.name}: $e');
                        if (mounted) showToast(context, 'Ошибка загрузки ${pf.name}', error: true);
                      }
                    }
                  }

                  // Нормализуем URL: localhost → реальный сервер
                  final fixedUrls = fileUrls.map(_fixFileUrl).toList();

                  // Встраиваем URL файлов в description (бэкенд не сохраняет file_urls)
                  final baseDesc = dc.text.trim();
                  final descWithFiles = fixedUrls.isEmpty
                      ? baseDesc
                      : baseDesc.isEmpty
                          ? fixedUrls.join('\n')
                          : '$baseDesc\n${fixedUrls.join('\n')}';

                  debugPrint('[CreateAssignment] fixedUrls=$fixedUrls descWithFiles=$descWithFiles');

                  final maxScore = int.tryParse(sc.text) ?? 100;
                  final filteredCriteria = criteria.where((c) => c['name'].toString().isNotEmpty).toList();
                  final finalCriteria = filteredCriteria.isEmpty
                      ? [{'name': 'Качество выполнения', 'weight': maxScore, 'description': ''}]
                      : filteredCriteria.map((c) => {'name': c['name'], 'weight': c['weight'], 'description': c['desc']}).toList();

                  await api.createAssignment({
                    'class_id': widget.classId,
                    'title': tc.text.trim(),
                    'description': descWithFiles,
                    'max_score': maxScore,
                    'criteria': finalCriteria,
                    if (deadline != null) 'deadline': deadline!.toIso8601String(),
                  });

                  Navigator.pop(ctx);
                  _loadAssignments();
                  showToast(context, fileUrls.isNotEmpty
                      ? 'Задание создано (${fileUrls.length} файл)'
                      : 'Задание создано');
                } catch (e) {
                  debugPrint('[CreateAssignment] Error: $e');
                  showToast(context, 'Ошибка: $e', error: true);
                }
              })),
          ]),
          SizedBox(height: 24),
        ]))));
  }

  Widget _fieldLabel2(String s) => Padding(padding: EdgeInsets.only(bottom: 8), child: Text(s, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.teal, letterSpacing: 1)));

  // ── Edit assignment ──
  void _editAssignment(dynamic a) {
    final rawDesc = a['description']?.toString() ?? '';
    // Показываем description БЕЗ встроенных URL (они хранятся там технически)
    final tc = TextEditingController(text: a['title'] ?? '');
    final dc = TextEditingController(text: _cleanContent(rawDesc));
    final sc = TextEditingController(text: '${a['max_score'] ?? 100}');
    DateTime? deadline;
    try { if (a['deadline'] != null) deadline = DateTime.parse(a['deadline']); } catch (_) {}

    // Извлекаем существующие URL из description (бэкенд хранит там)
    final existingUrls = _extractFilesFromText(rawDesc);
    List<String> keepUrls = List<String>.from(existingUrls);
    List<PlatformFile> newFiles = [];

    // Parse existing criteria
    List<Map<String, dynamic>> criteria = [];
    try {
      final raw = jsonDecode(a['criteria'] ?? '[]');
      criteria = (raw as List).map((c) => {'name': c['name'] ?? '', 'weight': c['weight'] ?? 0, 'desc': c['description'] ?? c['desc'] ?? ''}).toList();
    } catch (_) {}
    if (criteria.isEmpty) criteria = [{'name': '', 'weight': a['max_score'] ?? 100, 'desc': ''}];

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.9, maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(controller: scroll, padding: EdgeInsets.all(24), children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: Color(0xFFF59E0B).withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.edit_note_rounded, color: Color(0xFFF59E0B), size: 22)),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Редактировать задание', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text(a['title'] ?? '', style: TextStyle(fontSize: 12, color: C.text4), overflow: TextOverflow.ellipsis),
            ])),
            IconButton(icon: Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ]),
          SizedBox(height: 24),
          _fieldLabel2('НАЗВАНИЕ *'),
          TextField(controller: tc, decoration: InputDecoration(hintText: 'Название задания')),
          SizedBox(height: 16),
          _fieldLabel2('ОПИСАНИЕ'),
          TextField(controller: dc, decoration: InputDecoration(hintText: 'Описание и требования...'), maxLines: 4),
          SizedBox(height: 16),
          _fieldLabel2('МАКС. БАЛЛ'),
          TextField(controller: sc, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: '100')),
          SizedBox(height: 16),
          _fieldLabel2('ДЕДЛАЙН'),
          GestureDetector(onTap: () async {
            final d = await showDatePicker(context: ctx, initialDate: deadline ?? DateTime.now().add(Duration(days: 7)), firstDate: DateTime.now().subtract(Duration(days: 1)), lastDate: DateTime.now().add(Duration(days: 365)));
            if (d != null) {
              final t = await showTimePicker(context: ctx, initialTime: TimeOfDay(hour: deadline?.hour ?? 23, minute: deadline?.minute ?? 59));
              setS(() => deadline = DateTime(d.year, d.month, d.day, t?.hour ?? 23, t?.minute ?? 59));
            }
          }, child: Container(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Text(deadline != null ? '${deadline!.day.toString().padLeft(2,'0')}.${deadline!.month.toString().padLeft(2,'0')}.${deadline!.year} ${deadline!.hour.toString().padLeft(2,'0')}:${deadline!.minute.toString().padLeft(2,'0')}' : 'ДД.ММ.ГГГГ --:--', style: TextStyle(fontSize: 14, color: deadline != null ? null : C.text4)),
              Spacer(), Icon(Icons.calendar_today, size: 18, color: C.text4),
            ]))),
          SizedBox(height: 20),
          // Existing files
          if (keepUrls.isNotEmpty) ...[
            Row(children: [
              Text('ТЕКУЩИЕ ФАЙЛЫ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.teal, letterSpacing: 1)),
              Spacer(),
              Text('нажмите × для удаления', style: TextStyle(fontSize: 11, color: C.text4)),
            ]),
            SizedBox(height: 8),
            ...keepUrls.map((url) {
              final name = Uri.parse(url).pathSegments.last;
              return Container(margin: EdgeInsets.only(bottom: 6), padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: C.teal.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(Icons.insert_drive_file_outlined, size: 15, color: C.teal), SizedBox(width: 8),
                  Expanded(child: Text(name, style: TextStyle(fontSize: 13, color: C.teal), overflow: TextOverflow.ellipsis)),
                  GestureDetector(onTap: () => setS(() => keepUrls.remove(url)), child: Icon(Icons.close, size: 15, color: C.red)),
                ]));
            }),
            SizedBox(height: 12),
          ],
          // Add new files
          Row(children: [
            Text('ДОБАВИТЬ ФАЙЛЫ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.teal, letterSpacing: 1)),
            Spacer(),
            GestureDetector(
              onTap: () async {
                final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
                if (r != null) setS(() => newFiles.addAll(r.files));
              },
              child: Text('+ Добавить', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.teal)),
            ),
          ]),
          SizedBox(height: 8),
          if (newFiles.isNotEmpty) ...newFiles.map((f) => Container(margin: EdgeInsets.only(bottom: 6), padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: C.teal.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.insert_drive_file_outlined, size: 15, color: C.teal), SizedBox(width: 8),
              Expanded(child: Text(f.name, style: TextStyle(fontSize: 13, color: C.teal), overflow: TextOverflow.ellipsis)),
              GestureDetector(onTap: () => setS(() => newFiles.remove(f)), child: Icon(Icons.close, size: 15, color: C.text4)),
            ])))
          else Container(padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [Icon(Icons.attach_file, size: 15, color: C.text4), SizedBox(width: 8), Text('Нет новых файлов', style: TextStyle(fontSize: 13, color: C.text4))])),
          SizedBox(height: 24),
          // Criteria
          Row(children: [
            Text('КРИТЕРИИ ОЦЕНИВАНИЯ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.teal, letterSpacing: 1)),
            Spacer(),
            GestureDetector(onTap: () => setS(() => criteria.add({'name': '', 'weight': 0, 'desc': ''})),
              child: Text('+ Добавить', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.teal))),
          ]),
          SizedBox(height: 12),
          ...List.generate(criteria.length, (i) {
            final nameC   = TextEditingController(text: criteria[i]['name']);
            final weightC = TextEditingController(text: '${criteria[i]['weight']}');
            final descC   = TextEditingController(text: criteria[i]['desc'] ?? '');
            return Container(margin: EdgeInsets.only(bottom: 10), padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                Row(children: [
                  Text('${i+1}', style: TextStyle(fontSize: 12, color: C.text4)), SizedBox(width: 8),
                  Expanded(child: TextField(controller: nameC, decoration: InputDecoration(hintText: 'Критерий', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)), onChanged: (v) => criteria[i]['name'] = v)),
                  SizedBox(width: 8),
                  SizedBox(width: 60, child: TextField(controller: weightC, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: InputDecoration(contentPadding: EdgeInsets.symmetric(vertical: 10)), onChanged: (v) => criteria[i]['weight'] = int.tryParse(v) ?? 0)),
                  SizedBox(width: 4),
                  GestureDetector(onTap: () { if (criteria.length > 1) setS(() => criteria.removeAt(i)); }, child: Icon(Icons.close, size: 16, color: C.red)),
                ]),
                SizedBox(height: 6),
                TextField(controller: descC, decoration: InputDecoration(hintText: 'Описание критерия', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)), onChanged: (v) => criteria[i]['desc'] = v),
              ]));
          }),
          SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text('Отмена'), style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)))),
            SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(
              icon: Icon(Icons.check_rounded, size: 16, color: Colors.white),
              label: Text('Сохранить'),
              style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                if (tc.text.trim().isEmpty) return;
                try {
                  final api = context.read<ApiService>();
                  final uploadedUrls = <String>[];
                  for (final pf in newFiles) {
                    if (pf.path != null) {
                      try {
                        final res = await api.uploadFile(pf.path!, pf.name);
                        final url = res['url'] ?? res['file_url'] ?? res['path'];
                        if (url != null) uploadedUrls.add(url.toString());
                      } catch (_) {}
                    }
                  }
                  // Фиксируем URL (localhost → реальный сервер) и объединяем
                  final fixedNewUrls = uploadedUrls.map(_fixFileUrl).toList();
                  final fixedKeepUrls = keepUrls.map(_fixFileUrl).toList();
                  final allUrls = [...fixedKeepUrls, ...fixedNewUrls];

                  // Встраиваем URL файлов в description (бэкенд не сохраняет file_urls)
                  // Сначала очищаем description от старых встроенных URL, потом добавляем новые
                  final cleanDesc = _cleanContent(dc.text.trim());
                  final descWithFiles = allUrls.isEmpty
                      ? cleanDesc
                      : cleanDesc.isEmpty
                          ? allUrls.join('\n')
                          : '$cleanDesc\n${allUrls.join('\n')}';

                  final maxScore = int.tryParse(sc.text) ?? 100;
                  final finalCriteria = criteria.where((c) => c['name'].toString().isNotEmpty)
                      .map((c) => {'name': c['name'], 'weight': c['weight'], 'description': c['desc']}).toList();
                  await api.updateAssignment(a['id'], {
                    'title': tc.text.trim(),
                    'description': descWithFiles,
                    'max_score': maxScore,
                    'criteria': finalCriteria,
                    if (deadline != null) 'deadline': deadline!.toIso8601String(),
                  });
                  Navigator.pop(ctx); _loadAssignments(); showToast(context, 'Задание обновлено');
                } catch (e) { showToast(context, 'Ошибка: $e', error: true); }
              },
            )),
          ]),
          SizedBox(height: 24),
        ]),
      )),
    );
  }

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

// ── AI Chat widget (inside class) ──────────────────────────
class _AiChat extends StatefulWidget {
  final int classId;
  final String className;
  final String lectureContext;
  final List<String> lectureImageUrls;
  const _AiChat({required this.classId, required this.className, this.lectureContext = '', this.lectureImageUrls = const []});
  @override State<_AiChat> createState() => _AiChatState();
}

class _AiChatState extends State<_AiChat> with TickerProviderStateMixin {
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, String>> _msgs = [];
  bool _loading = false;
  late final AnimationController _pulseCtrl;
  late final AnimationController _fadeCtrl;

  static const _tips = [
    {'icon': Icons.menu_book_rounded,        'text': 'Объясни материал',   'color': C.teal},
    {'icon': Icons.lightbulb_outline_rounded,'text': 'Ключевые понятия',   'color': Color(0xFF6366F1)},
    {'icon': Icons.assignment_outlined,      'text': 'Помощь с заданием',  'color': Color(0xFFF59E0B)},
    {'icon': Icons.warning_amber_rounded,    'text': 'Частые ошибки',      'color': Color(0xFFEC4899)},
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _fadeCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
  }

  @override
  void dispose() { _pulseCtrl.dispose(); _fadeCtrl.dispose(); _ctrl.dispose(); _scroll.dispose(); super.dispose(); }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  void _send([String? override]) async {
    final text = override ?? _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    setState(() { _msgs.add({'role': 'user', 'text': text}); _loading = true; });
    _ctrl.clear();
    _scrollDown();
    try {
      final api = context.read<ApiService>();
      final lectureBlock = widget.lectureContext.isNotEmpty
          ? '\n\nМАТЕРИАЛЫ КУРСА (используй эти знания при ответах):\n${widget.lectureContext}' : '';
      final imgs = widget.lectureImageUrls;
      final List<Map<String, dynamic>> visionPre = imgs.isNotEmpty ? [
        {'role': 'user', 'content': [
          {'type': 'text', 'text': 'Прикреплённые файлы-изображения из материалов курса:'},
          ...imgs.map((url) => {'type': 'image_url', 'image_url': {'url': url, 'detail': 'low'}}),
        ]},
        {'role': 'assistant', 'content': 'Ознакомился с прикреплёнными материалами курса.'},
      ] : [];
      final apiMsgs = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'Ты AI-ассистент курса "${widget.className}". Отвечай на русском.$lectureBlock'},
        ...visionPre,
        ..._msgs.map((m) => {'role': m['role']!, 'content': m['text']!}),
      ];
      final data = await api.aiChat(apiMsgs, classId: widget.classId);
      setState(() => _msgs.add({'role': 'assistant', 'text': data['content'] ?? 'Нет ответа'}));
    } catch (_) {
      setState(() => _msgs.add({'role': 'assistant', 'text': 'Ошибка соединения'}));
    }
    if (mounted) { setState(() => _loading = false); _scrollDown(); }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final hasText = _ctrl.text.trim().isNotEmpty;

    return Column(children: [
      // Messages / empty state
      Expanded(child: _msgs.isEmpty ? _emptyState(isDark) : _messageList(isDark, surface)),

      // Input bar
      Container(
        padding: EdgeInsets.fromLTRB(12, 9, 12, MediaQuery.of(context).padding.bottom + 9),
        decoration: BoxDecoration(
          color: surface,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.18 : 0.05), blurRadius: 12, offset: Offset(0, -2))],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Container(
            decoration: BoxDecoration(
              color: adaptiveSurface2(context),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: hasText ? C.teal.withOpacity(0.28) : Colors.transparent, width: 1.5),
            ),
            child: TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                hintText: 'Спросите об этом курсе...',
                hintStyle: TextStyle(fontSize: 14, color: C.text4),
                border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                filled: false, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              ),
              onSubmitted: (_) => _send(),
              maxLines: 4, minLines: 1,
              onChanged: (_) => setState(() {}),
            ),
          )),
          SizedBox(width: 8),
          AnimatedContainer(
            duration: Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: !_loading ? LinearGradient(
                colors: hasText
                    ? [C.teal, C.tealDk]
                    : [C.teal.withOpacity(0.55), C.tealDk.withOpacity(0.45)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ) : null,
              color: _loading ? adaptiveSurface2(context) : null,
              borderRadius: BorderRadius.circular(14),
              boxShadow: hasText && !_loading ? tealGlow(opacity: 0.32) : null,
            ),
            child: GestureDetector(
              onTap: _send,
              child: _loading
                  ? Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: C.teal)))
                  : Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _emptyState(bool isDark) {
    final shortName = widget.className.length > 22 ? '${widget.className.substring(0, 22)}…' : widget.className;
    return FadeTransition(
      opacity: _fadeCtrl,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 28, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Logo with pulse
          AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) {
            final v = _pulseCtrl.value;
            return Stack(alignment: Alignment.center, children: [
              Container(width: 100, height: 100, decoration: BoxDecoration(shape: BoxShape.circle, color: C.teal.withOpacity(0.04 + v * 0.04))),
              Container(width: 76, height: 76, decoration: BoxDecoration(shape: BoxShape.circle, color: C.teal.withOpacity(0.07 + v * 0.04),
                boxShadow: [BoxShadow(color: C.teal.withOpacity(0.1 + v * 0.06), blurRadius: 20)])),
              Container(width: 56, height: 56,
                decoration: BoxDecoration(shape: BoxShape.circle, color: isDark ? C.darkSurface : Colors.white,
                  boxShadow: [BoxShadow(color: C.teal.withOpacity(0.16), blurRadius: 14, offset: Offset(0, 4))]),
                padding: EdgeInsets.all(12),
                child: Image.asset('assets/logo-icon.png', fit: BoxFit.contain)),
            ]);
          }),
          SizedBox(height: 18),
          Text('Чат по курсу', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4, color: adaptiveText1(context))),
          SizedBox(height: 4),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: C.teal.withOpacity(0.10), borderRadius: BorderRadius.circular(16)),
            child: Text(shortName, style: TextStyle(fontSize: 12, color: C.teal, fontWeight: FontWeight.w700)),
          ),
          SizedBox(height: 22),
          ..._tips.asMap().entries.map((e) {
            final i = e.key; final t = e.value;
            final color = t['color'] as Color;
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 350 + i * 70),
              curve: Curves.easeOutCubic,
              builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 10 * (1-v)), child: child)),
              child: GestureDetector(
                onTap: () => _send(t['text'] as String),
                child: Container(
                  margin: EdgeInsets.only(bottom: 9),
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? C.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withOpacity(0.18)),
                    boxShadow: [BoxShadow(color: color.withOpacity(0.06), blurRadius: 10, offset: Offset(0, 3))],
                  ),
                  child: Row(children: [
                    Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
                      child: Icon(t['icon'] as IconData, size: 17, color: color)),
                    SizedBox(width: 12),
                    Expanded(child: Text(t['text'] as String, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.2))),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: color),
                  ]),
                ),
              ),
            );
          }),
        ]),
      ),
    );
  }

  Widget _messageList(bool isDark, Color surface) {
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(14, 16, 14, 10),
      itemCount: _msgs.length + (_loading ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _msgs.length) return _typingIndicator(isDark, surface);
        final m   = _msgs[i];
        final isU = m['role'] == 'user';
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(
            offset: Offset(isU ? 12*(1-t) : -12*(1-t), 4*(1-t)), child: child)),
          child: isU ? _userBubble(m['text'] ?? '') : _aiBubble(m['text'] ?? '', isDark, surface),
        );
      },
    );
  }

  Widget _userBubble(String text) => Padding(
    padding: EdgeInsets.only(bottom: 14, left: 40),
    child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      Flexible(child: Container(
        padding: EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [C.teal, C.tealDk], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(20), bottomRight: Radius.circular(5)),
          boxShadow: tealGlow(opacity: 0.22),
        ),
        child: Text(text, style: TextStyle(fontSize: 14, color: Colors.white, height: 1.5)),
      )),
    ]),
  );

  Widget _aiBubble(String text, bool isDark, Color surface) => Padding(
    padding: EdgeInsets.only(bottom: 16, right: 28),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 30, height: 30,
        margin: EdgeInsets.only(top: 2, right: 9),
        decoration: BoxDecoration(
          color: isDark ? C.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: C.teal.withOpacity(0.22), width: 1.5),
          boxShadow: [BoxShadow(color: C.teal.withOpacity(0.08), blurRadius: 8)],
        ),
        padding: EdgeInsets.all(5),
        child: Image.asset('assets/logo-icon.png', fit: BoxFit.contain),
      ),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: EdgeInsets.only(left: 2, bottom: 4),
          child: Text('Chatra AI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.teal, letterSpacing: 0.2))),
        Container(
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? C.darkSurface : Colors.white,
            borderRadius: BorderRadius.only(topLeft: Radius.circular(5), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
            border: Border.all(color: C.teal.withOpacity(isDark ? 0.12 : 0.08)),
            boxShadow: softShadow(isDark),
          ),
          child: SelectableText(text, style: TextStyle(fontSize: 14, height: 1.65)),
        ),
      ])),
    ]),
  );

  Widget _typingIndicator(bool isDark, Color surface) => Padding(
    padding: EdgeInsets.only(bottom: 14, right: 28),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 30, height: 30,
        margin: EdgeInsets.only(top: 2, right: 9),
        decoration: BoxDecoration(
          color: isDark ? C.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: C.teal.withOpacity(0.22), width: 1.5),
        ),
        padding: EdgeInsets.all(5),
        child: Image.asset('assets/logo-icon.png', fit: BoxFit.contain),
      ),
      Container(
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? C.darkSurface : Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(5), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
          border: Border.all(color: C.teal.withOpacity(isDark ? 0.12 : 0.08)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => _ClassAiDot(delay: i * 180))),
      ),
    ]),
  );
}

class _ClassAiDot extends StatefulWidget {
  final int delay;
  const _ClassAiDot({required this.delay});
  @override State<_ClassAiDot> createState() => _ClassAiDotState();
}
class _ClassAiDotState extends State<_ClassAiDot> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: 500));
    Future.delayed(Duration(milliseconds: widget.delay), () { if (mounted) _c.repeat(reverse: true); });
    _a = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _a, builder: (_, __) => Container(
    width: 7, height: 7, margin: EdgeInsets.symmetric(horizontal: 3),
    decoration: BoxDecoration(color: C.teal.withOpacity(0.3 + _a.value * 0.7), shape: BoxShape.circle),
    transform: Matrix4.translationValues(0, -4 * _a.value, 0),
  ));
}
