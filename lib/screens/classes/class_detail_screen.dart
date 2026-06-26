import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart' show Options;
import '../../providers/auth_provider.dart';
import '../../providers/classes_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/class_utils.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/toast.dart';
import 'tabs/class_posts_tab.dart';
import 'tabs/class_assignments_tab.dart';
import 'tabs/class_ai_tab.dart';

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
  // Cached derived data — computed once in _load() instead of jsonDecode on every getter access.
  Map<String, dynamic> _meta = {};
  String _title = '';
  List<dynamic> _lectures = [];
  List<dynamic> _materials = [];
  bool _loading = true, _loadingAsg = false;
  bool _coverPrecached = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this, initialIndex: widget.initialTab);
    _tabCtrl.addListener(() { if (_tabCtrl.index == 2 && _assignments.isEmpty) _loadAssignments(); });
    _load();
    if (widget.initialTab == 2) _loadAssignments();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_coverPrecached) {
      _coverPrecached = true;
      final clsData = context.read<ClassesProvider>().allClasses
          .firstWhere((c) => c['id'] == widget.classId, orElse: () => <String, dynamic>{});
      final url = clsData['cover_image'];
      if (url != null && url.toString().isNotEmpty && !url.toString().startsWith('data:')) {
        precacheImage(CachedNetworkImageProvider(url.toString()), context);
      }
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final api = context.read<ApiService>();
    final isTeacher = context.read<AuthProvider>().isTeacher;
    // Posts and rating are independent — fetch them in parallel.
    final results = await Future.wait([
      api.getPosts().catchError((_) => _posts),
      isTeacher
          ? Future<Map<String, dynamic>>.value(_rating)
          : api.getMyRating(classId: widget.classId).catchError((_) => _rating),
    ]);
    _posts = results[0] as List<dynamic>;
    if (!isTeacher) _rating = results[1] as Map<String, dynamic>;
    _recomputeDerived();
    if (mounted) setState(() => _loading = false);
    _loadFileTexts();
  }

  // Parses post bodies once (after data arrives) and caches the results so that
  // build()/getters don't run jsonDecode on every access.
  void _recomputeDerived() {
    _lectures = _posts.where((p) => (p['title'] ?? '').startsWith('[LECTURE][${widget.classId}]')).toList();
    _materials = _posts.where((p) => (p['title'] ?? '').startsWith('[HW][${widget.classId}]')).toList();
    final metaPost = _posts.firstWhere(
      (p) => p['id'] == widget.classId && (() { try { return jsonDecode(p['body'])['type'] == 'class'; } catch (_) { return false; } })(),
      orElse: () => null,
    );
    _meta = metaPost != null
        ? (() { try { return jsonDecode(metaPost['body']) as Map<String, dynamic>; } catch (_) { return <String, dynamic>{}; } })()
        : <String, dynamic>{};
    _title = (_posts.firstWhere((p) => p['id'] == widget.classId, orElse: () => {'title': 'Класс #${widget.classId}'})['title'] ?? '') as String;
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
        final cleanUrl = _cleanFileUrl(url);
        try {
          final resp = await api.dio.get<Map<String, dynamic>>(
            '/upload/utils/file-text',
            queryParameters: {'url': cleanUrl},
          );
          final text = (resp.data?['text'] as String?) ?? '';
          if (text.isNotEmpty) result[url] = text;
        } catch (_) {}
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

  String _clean(String t) => t.replaceFirst(RegExp(r'^\[(LECTURE|HW)\]\[\d+\]\s*'), '').trim();
  String _fmtDate(String? d) { if (d == null) return ''; try { final dt = DateTime.parse(d); return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year}'; } catch (_) { return d; } }

  // Downloads the file and opens it with the native viewer (PDF, Word, Excel, images, etc.)
  Future<void> _openFileViewer(BuildContext ctx, String url, String name) async {
    final cleanUrl = _cleanFileUrl(url);
    final ext = name.split('.').last.toLowerCase();

    // Images — show in-app full-screen gallery
    final imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp'};
    if (imageExts.contains(ext)) {
      _showImageViewer(ctx, cleanUrl, name);
      return;
    }

    // Show download progress dialog
    var progress = 0.0;
    var cancelled = false;
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(builder: (dCtx, setD) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.10), shape: BoxShape.circle),
              child: Icon(_fileTypeConfig(ext)['icon'] as IconData, color: Theme.of(context).colorScheme.primary, size: 26),
            ),
            const SizedBox(height: 14),
            Text('Открытие файла', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(name, style: TextStyle(fontSize: 12, color: C.text4), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: StatefulBuilder(builder: (_, sp) => LinearProgressIndicator(value: progress > 0 ? progress : null, color: Theme.of(context).colorScheme.primary, backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.12), minHeight: 5)),
            ),
            const SizedBox(height: 10),
            Text(progress > 0 ? '${(progress * 100).toInt()}%' : 'Загрузка...', style: TextStyle(fontSize: 12, color: C.text4)),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () { cancelled = true; Navigator.pop(dCtx); },
              child: Text('Отмена', style: TextStyle(color: C.text4)),
            ),
          ]),
        );
      }),
    );

    try {
      final dir = await getTemporaryDirectory();
      final safeFileName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final filePath = '${dir.path}/$safeFileName';
      final file = File(filePath);

      // Use cached version if it exists
      if (!await file.exists()) {
        final api = context.read<ApiService>();
        await api.dio.download(
          cleanUrl,
          filePath,
          onReceiveProgress: (received, total) {
            if (total > 0) progress = received / total;
          },
          options: Options(receiveTimeout: const Duration(minutes: 5)),
        );
      }

      if (!mounted || cancelled) return;
      Navigator.pop(context);

      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done && mounted) {
        // Fallback to browser if native open fails
        await launchUrl(Uri.parse(cleanUrl), mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (!mounted || cancelled) return;
      Navigator.pop(context);
      try { await launchUrl(Uri.parse(cleanUrl), mode: LaunchMode.externalApplication); } catch (_) {}
    }
  }

  void _showImageViewer(BuildContext ctx, String url, String name) {
    showDialog(
      context: ctx,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(children: [
            Center(child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholder: (_, __) => Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary, strokeWidth: 2)),
                errorWidget: (_, __, ___) => Icon(CupertinoIcons.photo, color: Colors.white54, size: 64),
              ),
            )),
            Positioned(top: MediaQuery.of(ctx).padding.top + 8, right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 18)),
              )),
            Positioned(bottom: MediaQuery.of(ctx).padding.bottom + 16, left: 0, right: 0,
              child: Center(child: Text(name, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis))),
          ]),
        ),
      ),
    );
  }

  // Returns the human-readable filename: uses the URL fragment (#OriginalName.pdf) if present,
  // otherwise falls back to the last path segment (which may be a UUID).
  String _fileDisplayName(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.fragment.isNotEmpty) return Uri.decodeComponent(uri.fragment);
      return uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => url);
    } catch (_) { return url; }
  }

  // Strips the #fragment from a URL before passing it to launchUrl or fetching.
  String _cleanFileUrl(String url) {
    final idx = url.indexOf('#');
    return idx >= 0 ? url.substring(0, idx) : url;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final auth = context.watch<AuthProvider>();
    final meta = _meta;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = Theme.of(context).colorScheme.surface;

    // Use ClassesProvider data immediately (available before _load() completes)
    // so CachedNetworkImage mounts during the page-push animation, not after.
    final clsData = context.read<ClassesProvider>().allClasses
        .firstWhere((c) => c['id'] == widget.classId, orElse: () => <String, dynamic>{});
    final coverImg = meta['cover_image'] ?? clsData['cover_image'];
    final displayTitle = _title.isNotEmpty ? _title : (clsData['title'] ?? '');
    final displayDesc = (meta['description'] ?? clsData['description'] ?? '').toString();

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            forceMaterialTransparency: true,
            leading: IconButton(
              padding: EdgeInsets.zero,
              icon: Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)), child: const Icon(CupertinoIcons.chevron_left, color: Colors.white, size: 20)),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (auth.isTeacher) IconButton(
                padding: EdgeInsets.zero,
                icon: Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)), child: const Icon(CupertinoIcons.pencil, color: Colors.white70, size: 18)),
                onPressed: () => _editClass(),
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              titlePadding: EdgeInsets.zero,
              background: Stack(fit: StackFit.expand, children: [
                Container(decoration: BoxDecoration(gradient: LinearGradient(
                  colors: [Color(0xFF006475), Theme.of(context).colorScheme.primary],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ))),
                if (coverImg != null && !coverImg.toString().startsWith('data:'))
                  RepaintBoundary(child: Image(
                    image: CachedNetworkImageProvider(coverImg.toString()),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  )),
                if (coverImg != null && coverImg.toString().startsWith('data:'))
                  Builder(builder: (_) {
                    try { return Image.memory(base64Decode(coverImg.toString().split(',').last), fit: BoxFit.cover, alignment: Alignment.topCenter); }
                    catch (_) { return const SizedBox.shrink(); }
                  }),
                Container(decoration: const BoxDecoration(gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  stops: [0.0, 0.4, 1.0],
                  colors: [Colors.black38, Colors.transparent, Colors.black54],
                ))),
                Positioned(bottom: 16, left: 16, right: 16, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(displayTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white, shadows: [Shadow(color: Colors.black54, blurRadius: 6)]), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (displayDesc.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(displayDesc, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                  if (auth.isTeacher) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () { Clipboard.setData(ClipboardData(text: classCode(widget.classId))); showToast(context, '${l.t('code_copied')}: ${classCode(widget.classId)}'); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: adaptivePrimaryLt(context).withOpacity(0.9), borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(CupertinoIcons.doc_on_doc, size: 14, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 6),
                          Text('${l.t('class_code')}: ', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary)),
                          Text(classCode(widget.classId), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary, letterSpacing: 2)),
                        ]),
                      ),
                    ),
                  ],
                ])),
              ]),
            ),
          ),
        ],
        body: Column(children: [
          // ── TabBar + teacher action buttons ────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: surfaceColor,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.18 : 0.05), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(children: [
              TabBar(
                controller: _tabCtrl,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: C.text4,
                indicatorColor: Theme.of(context).colorScheme.primary,
                indicatorWeight: 2,
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: Colors.transparent,
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.1),
                unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                tabs: [
                  Tab(icon: const Icon(CupertinoIcons.book, size: 19), iconMargin: const EdgeInsets.only(bottom: 3), text: '${l.t('lectures')} (${_lectures.length})', height: 58),
                  Tab(icon: const Icon(CupertinoIcons.square_stack_3d_down_right, size: 19), iconMargin: const EdgeInsets.only(bottom: 3), text: l.t('materials'), height: 58),
                  Tab(icon: const Icon(CupertinoIcons.list_bullet, size: 19), iconMargin: const EdgeInsets.only(bottom: 3), text: l.t('assignments'), height: 58),
                  Tab(icon: const Icon(CupertinoIcons.sparkles, size: 19), iconMargin: const EdgeInsets.only(bottom: 3), text: l.t('ai_chat'), height: 58),
                ],
              ),
              if (auth.isTeacher) AnimatedBuilder(animation: _tabCtrl, builder: (ctx, _) {
                if (_tabCtrl.index == 3) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Row(children: [
                    Expanded(child: GestureDetector(
                      onTap: () => _createAssignment(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(13), border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.28))),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(CupertinoIcons.doc, size: 15, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 6),
                          Text(l.t('assignment'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                        ]),
                      ),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: GestureDetector(
                      onTap: () => _showAddMenu(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary]), borderRadius: BorderRadius.circular(13), boxShadow: primaryGlow(Theme.of(context).colorScheme.primary, opacity: 0.28)),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(CupertinoIcons.plus, size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(l.t('add'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                        ]),
                      ),
                    )),
                  ]),
                );
              }),
            ]),
          ),
          // ── Tab content ─────────────────────────────────────────────────────
          Expanded(child: _loading
            ? CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
                SliverFillRemaining(hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))),
              ])
            : TabBarView(controller: _tabCtrl, children: [
                ClassPostsTab(
                  posts: _lectures, type: 'lecture', isTeacher: auth.isTeacher, fileTexts: _fileTexts,
                  onShowPost: _showPost, onEditPost: _editPost,
                  onDeletePost: (id) async { try { await context.read<ApiService>().deletePost(id); _load(); } catch (_) {} },
                ),
                ClassPostsTab(
                  posts: _materials, type: 'material', isTeacher: auth.isTeacher, fileTexts: _fileTexts,
                  onShowPost: _showPost, onEditPost: _editPost,
                  onDeletePost: (id) async { try { await context.read<ApiService>().deletePost(id); _load(); } catch (_) {} },
                ),
                ClassAssignmentsTab(
                  assignments: _assignments, mySubs: _mySubs, rating: _rating,
                  isTeacher: auth.isTeacher, classId: widget.classId, isLoading: _loadingAsg,
                  onRefresh: _loadAssignments, onEditAssignment: _editAssignment,
                  onOpenFile: (url, name) => _openFileViewer(context, url, name),
                ),
                _aiTab(),
              ]),
          ),
        ]),
      ),
      floatingActionButton: null,
    );
  }

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
                final name = _fileDisplayName(f.toString());
                return Container(
                  margin: EdgeInsets.only(bottom: 6),
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Icon(CupertinoIcons.doc, size: 14, color: Theme.of(context).colorScheme.primary),
                    SizedBox(width: 6),
                    Expanded(child: Text(name, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary), overflow: TextOverflow.ellipsis)),
                    GestureDetector(onTap: () => setS(() => editFiles.remove(f)), child: Icon(CupertinoIcons.xmark, size: 14, color: C.text4)),
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
                        if (url != null) setS(() => editFiles.add('${url}#${Uri.encodeComponent(pf.name)}'));
                      } catch (_) {}
                    }
                  }
                }
              },
              child: Container(padding: EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3))),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(CupertinoIcons.paperclip, size: 16, color: Theme.of(context).colorScheme.primary), SizedBox(width: 6), Text('Прикрепить файлы', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600))])),
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
      })).then((_) { tc.dispose(); cc.dispose(); });
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


  // ── AI Chat tab ──
  String get _lectureContextForAI {
    final all = [..._lectures, ..._materials].take(12);
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
      if (content.length > 4000) content = content.substring(0, 4000);
      final sb = StringBuffer();
      if (title.isNotEmpty) sb.write('### $title\n');
      if (content.isNotEmpty) sb.write(content);
      if (files.isNotEmpty) {
        for (final f in files) {
          final url = _fixFileUrl(f.toString());
          final name = _fileDisplayName(url);
          final ext = _cleanFileUrl(url).split('?').first.split('.').last.toLowerCase();
          if (_fileTexts.containsKey(url)) {
            var text = _fileTexts[url]!;
            if (text.length > 5000) text = '${text.substring(0, 5000)}...';
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
        final ext = _cleanFileUrl(f).split('?').first.split('.').last.toLowerCase();
        if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) urls.add(f);
        if (urls.length >= 3) return urls;
      }
    }
    return urls;
  }

  Widget _aiTab() => ClassAiTab(classId: widget.classId, className: _title, lectureContext: _lectureContextForAI, lectureImageUrls: _lectureImageUrls);

  // ── Show post detail ──
  void _showPost(dynamic p, String type, int num) {
    String content = '';
    try { final b = jsonDecode(p['body']); content = b['content'] ?? b['description'] ?? ''; }
    catch (_) { content = p['body'] ?? ''; }
    final files    = _extractFiles(p);
    final cleanText = _cleanContent(content);
    final isLecture = type == 'lecture';
    final accent    = Theme.of(context).colorScheme.primary;
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
                  colors: [Color(0xFF006475), Theme.of(context).colorScheme.primary],
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
                      child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 16),
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
                  Icon(CupertinoIcons.calendar, size: 12, color: Colors.white60),
                  const SizedBox(width: 5),
                  Text(_fmtDate(p['created_at'] ?? ''), style: const TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w500)),
                  if (files.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Container(width: 4, height: 4, decoration: BoxDecoration(color: Colors.white30, shape: BoxShape.circle)),
                    const SizedBox(width: 12),
                    Icon(CupertinoIcons.paperclip, size: 12, color: Colors.white60),
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
                    final name = _fileDisplayName(f);
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
                        onTap: () => _openFileViewer(context, f, name),
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
                              child: Icon(CupertinoIcons.arrow_up_right_square, size: 16, color: fileColor),
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
                        child: Icon(isLecture ? CupertinoIcons.book : CupertinoIcons.tray, size: 30, color: accent)),
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

  Map<String, dynamic> _fileTypeConfig(String ext) {
    switch (ext) {
      case 'pdf':
        return {'icon': CupertinoIcons.doc_text, 'color': const Color(0xFFE53E3E), 'bg': const Color(0xFFFFF5F5)};
      case 'pptx': case 'ppt':
        return {'icon': CupertinoIcons.film,       'color': const Color(0xFFDD6B20), 'bg': const Color(0xFFFFFAF0)};
      case 'doc': case 'docx':
        return {'icon': CupertinoIcons.doc_text,    'color': const Color(0xFF2B6CB0), 'bg': const Color(0xFFEBF8FF)};
      case 'xlsx': case 'xls':
        return {'icon': CupertinoIcons.square_grid_2x2,    'color': const Color(0xFF276749), 'bg': const Color(0xFFF0FFF4)};
      case 'txt': case 'md':
        return {'icon': CupertinoIcons.doc_plaintext,   'color': const Color(0xFF553C9A), 'bg': const Color(0xFFFAF5FF)};
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp':
        return {'icon': CupertinoIcons.photo,          'color': const Color(0xFF0C4A6E), 'bg': const Color(0xFFE0F2FE)};
      case 'mp4': case 'mov': case 'avi':
        return {'icon': CupertinoIcons.play_circle,    'color': const Color(0xFF6B21A8), 'bg': const Color(0xFFF5F3FF)};
      default:
        return {'icon': CupertinoIcons.doc, 'color': C.text4,             'bg': C.surface2};
    }
  }

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
            Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(CupertinoIcons.book, color: Theme.of(context).colorScheme.primary, size: 22)),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Добавить лекцию', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text('Учебный материал для класса', style: TextStyle(fontSize: 12, color: C.text4)),
            ])),
            IconButton(icon: Icon(CupertinoIcons.xmark), onPressed: () => Navigator.pop(ctx)),
          ]),
          SizedBox(height: 20),
          // Type toggle
          Container(decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Expanded(child: GestureDetector(onTap: () => setS(() => type = 'lecture'),
                child: Container(padding: EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: type == 'lecture' ? Theme.of(ctx).colorScheme.surface : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(CupertinoIcons.book, size: 16, color: type == 'lecture' ? Theme.of(context).colorScheme.primary : C.text4), SizedBox(width: 6), Text('Лекция', style: TextStyle(fontWeight: FontWeight.w600, color: type == 'lecture' ? Theme.of(context).colorScheme.primary : C.text4))])))),
              Expanded(child: GestureDetector(onTap: () => setS(() => type = 'material'),
                child: Container(padding: EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: type == 'material' ? Theme.of(ctx).colorScheme.surface : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(CupertinoIcons.doc_text, size: 16, color: type == 'material' ? Theme.of(context).colorScheme.primary : C.text4), SizedBox(width: 6), Text('Материал', style: TextStyle(fontWeight: FontWeight.w600, color: type == 'material' ? Theme.of(context).colorScheme.primary : C.text4))])))),
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
          }, child: Container(padding: EdgeInsets.all(20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3))),
            child: Column(children: [
              Icon(CupertinoIcons.arrow_up_doc, size: 24, color: Theme.of(context).colorScheme.primary), SizedBox(height: 6),
              RichText(text: TextSpan(style: TextStyle(fontSize: 13, color: C.text4), children: [TextSpan(text: 'Нажмите или '), TextSpan(text: 'выберите файлы', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary))])),
              Text('PDF, DOCX, PPT, изображения', style: TextStyle(fontSize: 10, color: C.text4)),
            ]))),
          if (lectureFiles.isNotEmpty) ...[SizedBox(height: 8),
            ...lectureFiles.map((f) => Container(margin: EdgeInsets.only(bottom: 4), padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [Icon(CupertinoIcons.doc_text, size: 14, color: Theme.of(context).colorScheme.primary), SizedBox(width: 6), Expanded(child: Text(f.name, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary), overflow: TextOverflow.ellipsis)), GestureDetector(onTap: () => setS(() => lectureFiles.remove(f)), child: Icon(CupertinoIcons.xmark, size: 14, color: C.text4))])))],
          SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text('Отмена'), style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)))),
            SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(icon: Icon(CupertinoIcons.plus, size: 16, color: Colors.white), label: Text('Опубликовать'),
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
                        if (url != null) fileUrls.add('${url}#${Uri.encodeComponent(pf.name)}');
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
        ])))).then((_) { tc.dispose(); cc.dispose(); });
  }

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
            Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
              child: Icon(CupertinoIcons.pencil, color: Theme.of(context).colorScheme.primary, size: 22)),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Новое задание', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text('Заполните данные задания', style: TextStyle(fontSize: 12, color: C.text4)),
            ])),
            IconButton(icon: Icon(CupertinoIcons.xmark), onPressed: () => Navigator.pop(ctx)),
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
              Spacer(), Icon(CupertinoIcons.calendar, size: 18, color: C.text4),
            ]))),
          SizedBox(height: 20),
          // File attachments
          Row(children: [
            Text('ПРИКРЕПЛЁННЫЕ ФАЙЛЫ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1)),
            Spacer(),
            GestureDetector(
              onTap: () async {
                final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
                if (result != null) setS(() => attachedFiles.addAll(result.files));
              },
              child: Text('+ Добавить', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
            ),
          ]),
          SizedBox(height: 8),
          if (attachedFiles.isEmpty)
            Container(padding: EdgeInsets.all(14), decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [Icon(CupertinoIcons.paperclip, size: 16, color: C.text4), SizedBox(width: 8), Text('Нет прикреплённых файлов', style: TextStyle(fontSize: 13, color: C.text4))]))
          else
            ...attachedFiles.map((f) => Container(margin: EdgeInsets.only(bottom: 6), padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(CupertinoIcons.doc, size: 16, color: Theme.of(context).colorScheme.primary),
                SizedBox(width: 8),
                Expanded(child: Text(f.name, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: () => setS(() => attachedFiles.removeWhere((x) => x.name == f.name)),
                  child: Icon(CupertinoIcons.xmark, size: 14, color: C.text4)),
              ]))),
          SizedBox(height: 20),
          // Reference solution
          Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.15))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 36, height: 36, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                  child: Icon(CupertinoIcons.checkmark_circle, size: 18, color: Theme.of(context).colorScheme.primary)),
                SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Text('Эталонные решения', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)), Spacer(), Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text('ИИ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)))]),
                  Text('ИИ сравнит работы учеников с эталоном', style: TextStyle(fontSize: 11, color: C.text4)),
                ])),
              ]),
              SizedBox(height: 12),
              GestureDetector(onTap: () async {
                final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
                if (result != null) setS(() => referenceFiles.addAll(result.files));
              },
              child: Container(padding: EdgeInsets.all(20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3))),
                child: Column(children: [
                  Icon(CupertinoIcons.arrow_up_doc, size: 28, color: Theme.of(context).colorScheme.primary),
                  SizedBox(height: 6),
                  RichText(text: TextSpan(style: TextStyle(fontSize: 13, color: C.text4), children: [TextSpan(text: 'Нажмите или '), TextSpan(text: 'выберите файлы', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary))])),
                  Text('PDF, DOCX, DOC, PPTX, XLSX, TXT, MD', style: TextStyle(fontSize: 10, color: C.text4)),
                ]))),
              if (referenceFiles.isNotEmpty) ...[
                SizedBox(height: 8),
                ...referenceFiles.map((f) => Container(margin: EdgeInsets.only(bottom: 4), padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [Icon(CupertinoIcons.doc_text, size: 14, color: Theme.of(context).colorScheme.primary), SizedBox(width: 6), Expanded(child: Text(f.name, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary), overflow: TextOverflow.ellipsis)), GestureDetector(onTap: () => setS(() => referenceFiles.remove(f)), child: Icon(CupertinoIcons.xmark, size: 14, color: C.text4))]))),
              ],
            ])),
          SizedBox(height: 20),
          // Criteria
          Row(children: [
            Text('КРИТЕРИИ ОЦЕНИВАНИЯ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1)),
            Spacer(),
            GestureDetector(onTap: () => setS(() => criteria.add({'name': '', 'weight': 0, 'desc': ''})),
              child: Text('+ Добавить', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary))),
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
                  GestureDetector(onTap: () { if (criteria.length > 1) setS(() => criteria.removeAt(i)); }, child: Icon(CupertinoIcons.xmark, size: 16, color: C.red)),
                ]),
                SizedBox(height: 6),
                TextField(controller: descC, decoration: InputDecoration(hintText: 'Описание (необязательно)', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)), onChanged: (v) => criteria[i]['desc'] = v),
              ]));
          }),
          SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text('Отмена'), style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)))),
            SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(icon: Icon(CupertinoIcons.plus, size: 16, color: Colors.white), label: Text('Создать задание'),
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
                          fileUrls.add('${url}#${Uri.encodeComponent(pf.name)}');
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
        ])))).then((_) { tc.dispose(); dc.dispose(); sc.dispose(); });
  }

  Widget _fieldLabel2(String s) => Padding(padding: EdgeInsets.only(bottom: 8), child: Text(s, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1)));

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
              child: Icon(CupertinoIcons.pencil, color: Color(0xFFF59E0B), size: 22)),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Редактировать задание', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text(a['title'] ?? '', style: TextStyle(fontSize: 12, color: C.text4), overflow: TextOverflow.ellipsis),
            ])),
            IconButton(icon: Icon(CupertinoIcons.xmark), onPressed: () => Navigator.pop(ctx)),
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
              Spacer(), Icon(CupertinoIcons.calendar, size: 18, color: C.text4),
            ]))),
          SizedBox(height: 20),
          // Existing files
          if (keepUrls.isNotEmpty) ...[
            Row(children: [
              Text('ТЕКУЩИЕ ФАЙЛЫ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1)),
              Spacer(),
              Text('нажмите × для удаления', style: TextStyle(fontSize: 11, color: C.text4)),
            ]),
            SizedBox(height: 8),
            ...keepUrls.map((url) {
              final name = _fileDisplayName(url);
              return Container(margin: EdgeInsets.only(bottom: 6), padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(CupertinoIcons.doc, size: 15, color: Theme.of(context).colorScheme.primary), SizedBox(width: 8),
                  Expanded(child: Text(name, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary), overflow: TextOverflow.ellipsis)),
                  GestureDetector(onTap: () => setS(() => keepUrls.remove(url)), child: Icon(CupertinoIcons.xmark, size: 15, color: C.red)),
                ]));
            }),
            SizedBox(height: 12),
          ],
          // Add new files
          Row(children: [
            Text('ДОБАВИТЬ ФАЙЛЫ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1)),
            Spacer(),
            GestureDetector(
              onTap: () async {
                final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
                if (r != null) setS(() => newFiles.addAll(r.files));
              },
              child: Text('+ Добавить', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
            ),
          ]),
          SizedBox(height: 8),
          if (newFiles.isNotEmpty) ...newFiles.map((f) => Container(margin: EdgeInsets.only(bottom: 6), padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(CupertinoIcons.doc, size: 15, color: Theme.of(context).colorScheme.primary), SizedBox(width: 8),
              Expanded(child: Text(f.name, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary), overflow: TextOverflow.ellipsis)),
              GestureDetector(onTap: () => setS(() => newFiles.remove(f)), child: Icon(CupertinoIcons.xmark, size: 15, color: C.text4)),
            ])))
          else Container(padding: EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [Icon(CupertinoIcons.paperclip, size: 15, color: C.text4), SizedBox(width: 8), Text('Нет новых файлов', style: TextStyle(fontSize: 13, color: C.text4))])),
          SizedBox(height: 24),
          // Criteria
          Row(children: [
            Text('КРИТЕРИИ ОЦЕНИВАНИЯ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1)),
            Spacer(),
            GestureDetector(onTap: () => setS(() => criteria.add({'name': '', 'weight': 0, 'desc': ''})),
              child: Text('+ Добавить', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary))),
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
                  GestureDetector(onTap: () { if (criteria.length > 1) setS(() => criteria.removeAt(i)); }, child: Icon(CupertinoIcons.xmark, size: 16, color: C.red)),
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
              icon: Icon(CupertinoIcons.checkmark, size: 16, color: Colors.white),
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
                        if (url != null) uploadedUrls.add('${url}#${Uri.encodeComponent(pf.name)}');
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
    ).then((_) { tc.dispose(); dc.dispose(); sc.dispose(); });
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
            Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(CupertinoIcons.pencil, color: Theme.of(context).colorScheme.primary, size: 22)),
            SizedBox(width: 12),
            Expanded(child: Text('Редактировать класс', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            IconButton(icon: Icon(CupertinoIcons.xmark), onPressed: () => Navigator.pop(ctx)),
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
            child: Container(height: 150, decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3), width: 1.5)),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                if (newCoverBase64 != null && newCoverBase64!.startsWith('data:'))
                  Builder(builder: (_) { try { return Image.memory(base64Decode(newCoverBase64!.split(',').last), fit: BoxFit.cover); } catch (_) { return Container(color: Theme.of(context).colorScheme.primary.withOpacity(0.1)); } })
                else if (newCoverBase64 != null)
                  CachedNetworkImage(imageUrl: newCoverBase64!, fit: BoxFit.cover, fadeInDuration: Duration.zero, fadeOutDuration: Duration.zero, placeholder: (_, __) => const SizedBox.shrink(), errorWidget: (_, __, ___) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF006475), Theme.of(context).colorScheme.primary]))))
                else
                  Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF006475), Theme.of(context).colorScheme.primary], begin: Alignment.topLeft, end: Alignment.bottomRight))),
                // Overlay
                Container(color: Colors.black.withOpacity(0.3),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(CupertinoIcons.photo, color: Colors.white, size: 32),
                    SizedBox(height: 6),
                    Text(newCoverBase64 != null ? 'Нажмите для замены' : 'Выбрать обложку', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  ])),
              ])),
          ),
          if (newCoverBase64 != null) ...[
            SizedBox(height: 8),
            GestureDetector(onTap: () => setS(() => newCoverBase64 = null),
              child: Row(children: [Icon(CupertinoIcons.xmark, size: 14, color: C.red), SizedBox(width: 4), Text('Убрать обложку', style: TextStyle(fontSize: 12, color: C.red))])),
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
        ])))).then((_) { tc.dispose(); dc.dispose(); tn.dispose(); });
  }

  @override void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }
}

