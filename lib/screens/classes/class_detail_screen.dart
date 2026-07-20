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
import 'package:dio/dio.dart' show Options, CancelToken, DioException;
import '../../providers/auth_provider.dart';
import '../../providers/classes_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../utils/image_cache.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/toast.dart';
import 'tabs/class_posts_tab.dart';
import 'tabs/class_assignments_tab.dart';
import 'tabs/class_ai_tab.dart';
import 'tabs/class_avatar_tab.dart';
import 'rollover_screen.dart';
import 'class_detail_utils.dart';
import 'widgets/class_cover_sliver.dart';

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
  String _cachedLectureContext = '';
  List<String> _cachedLectureImageUrls = [];
  Map<String, dynamic> _classData = {};
  Map<String, dynamic> _meta = {};
  String _title = '';
  List<dynamic> _lectures = [];
  List<dynamic> _materials = [];
  bool _loading = true, _loadingAsg = false, _aiTabActive = false, _avatarTabActive = false;
  bool _coverPrecached = false;
  Widget? _headerCache;
  String _headerSig = '';
  int? _avatarLectureCount;
  List<dynamic> _cohorts = [];
  int? _selectedCohortId;

  bool get _canManageCohorts {
    final auth = context.read<AuthProvider>();
    if (!auth.isTeacher) return false;
    if (auth.isAdmin) return true;
    final createdBy = _meta['created_by'] ?? _classData['created_by'];
    return createdBy != null && (createdBy as num).toInt() == auth.userId;
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this, initialIndex: widget.initialTab);
    _aiTabActive = widget.initialTab == 3;
    _avatarTabActive = widget.initialTab == 4;
    _tabCtrl.addListener(() {
      if (_tabCtrl.index == 2 && _assignments.isEmpty) _loadAssignments();
      if (_tabCtrl.indexIsChanging) {
        HapticFeedback.selectionClick();
      } else {
        final isAi = _tabCtrl.index == 3;
        final isAvatar = _tabCtrl.index == 4;
        if (_aiTabActive != isAi || _avatarTabActive != isAvatar) {
          setState(() { _aiTabActive = isAi; _avatarTabActive = isAvatar; });
        }
      }
    });
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
      final rawUrl = clsData['cover_image'];
      if (rawUrl != null && rawUrl.toString().isNotEmpty && !rawUrl.toString().startsWith('data:')) {
        final url = context.read<ApiService>().fixUrl(rawUrl.toString());
        precacheImage(
          ResizeImage(
            CachedNetworkImageProvider(url, cacheKey: 'class_cover_${widget.classId}'),
            width: 800,
          ),
          context,
        );
      }
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final api = context.read<ApiService>();
    final isTeacher = context.read<AuthProvider>().isTeacher;
    final results = await Future.wait([
      api.getClass(widget.classId).catchError((_) => _classData),
      api.getPosts(classId: widget.classId).catchError((_) => _posts),
      isTeacher
          ? Future<Map<String, dynamic>>.value(_rating)
          : api.getMyRating(classId: widget.classId).catchError((_) => _rating),
    ]);
    _classData = results[0] as Map<String, dynamic>;
    _posts = results[1] as List<dynamic>;
    if (!isTeacher) _rating = results[2] as Map<String, dynamic>;
    _recomputeDerived();
    if (mounted) setState(() => _loading = false);
    _loadFileTexts();
    if (_canManageCohorts) _loadCohorts();
  }

  Future<void> _evictCoverCache(String? newUrl) async {
    try {
      final fixed = (newUrl != null && newUrl.isNotEmpty)
          ? context.read<ApiService>().fixUrl(newUrl) : '';
      await CachedNetworkImage.evictFromCache(fixed, cacheKey: 'class_cover_${widget.classId}');
    } catch (_) {}
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  void _applyClassUpdate(Map<String, dynamic> updated) {
    if (mounted) {
      setState(() {
        _classData = {..._classData, ...updated};
        _recomputeDerived();
      });
    }
    context.read<ClassesProvider>().patchCachedClass(widget.classId, updated);
  }

  Future<void> _loadCohorts() async {
    try {
      final cohorts = await context.read<ApiService>().getClassCohorts(widget.classId);
      if (!mounted) return;
      setState(() => _cohorts = cohorts);
    } catch (_) {}
  }

  void _recomputeDerived() {
    _lectures = _posts.where((p) => (p['title'] ?? '').startsWith('[LECTURE][${widget.classId}]')).toList();
    _materials = _posts.where((p) => (p['title'] ?? '').startsWith('[HW][${widget.classId}]')).toList();
    _meta = _classData;
    _title = (_classData['name'] ?? '${context.read<L10n>().t('class_label')} #${widget.classId}').toString();
    _recomputeAiContext();
  }

  void _recomputeAiContext() {
    final all = [..._lectures, ..._materials].take(12);
    final parts = <String>[];
    for (final p in all) {
      final title = cleanPostTitle(p['title'] ?? '');
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
          final url = context.read<ApiService>().fixUrl(f.toString());
          final name = fileDisplayName(url);
          final ext = cleanFileUrl(url).split('?').first.split('.').last.toLowerCase();
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
    _cachedLectureContext = parts.join('\n\n');

    final allPosts = [..._lectures, ..._materials];
    final urls = <String>[];
    for (final p in allPosts) {
      for (final f in _extractFiles(p)) {
        final ext = cleanFileUrl(f).split('?').first.split('.').last.toLowerCase();
        if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) urls.add(f);
        if (urls.length >= 3) break;
      }
      if (urls.length >= 3) break;
    }
    _cachedLectureImageUrls = urls;
  }

  Future<void> _loadFileTexts() async {
    if (!mounted) return;
    final api = context.read<ApiService>();
    final result = <String, String>{};

    final filePairs = <({String url, String cleanUrl})>[];
    for (final p in [..._lectures, ..._materials]) {
      List<dynamic> files = [];
      try {
        final b = jsonDecode(p['body'] ?? '');
        if (b['files'] is List) files = b['files'] as List;
      } catch (_) {}
      for (final f in files) {
        final url = context.read<ApiService>().fixUrl(f.toString());
        filePairs.add((url: url, cleanUrl: cleanFileUrl(url)));
      }
    }

    const maxConcurrent = 3;
    for (var i = 0; i < filePairs.length; i += maxConcurrent) {
      final chunk = filePairs.skip(i).take(maxConcurrent);
      await Future.wait(chunk.map((pair) async {
        try {
          final resp = await api.dio.get<Map<String, dynamic>>(
            '/upload/utils/file-text',
            queryParameters: {'url': pair.cleanUrl},
          );
          final text = (resp.data?['text'] as String?) ?? '';
          if (text.isNotEmpty) result[pair.url] = text;
        } catch (_) {}
      }));
    }

    if (mounted) {
      setState(() {
      _fileTexts = result;
      _recomputeAiContext();
    });
    }
  }

  Future<void> _loadAssignments() async {
    if (!mounted) return; setState(() => _loadingAsg = true);
    final api = context.read<ApiService>();
    final isTeacher = context.read<AuthProvider>().isTeacher;
    await Future.wait([
      () async { try { _assignments = await api.getAssignments(classId: widget.classId); } catch (_) {} }(),
      () async { if (!isTeacher) { try { _mySubs = await api.getMySubmissions(); } catch (_) {} } }(),
    ]);
    if (mounted) setState(() => _loadingAsg = false);
  }

  Widget _tabItem(IconData icon, String label) {
    return Tab(
      height: 58,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 19),
        const SizedBox(height: 3),
        FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, softWrap: false)),
      ]),
    );
  }

  Future<void> _openFileViewer(BuildContext ctx, String url, String name) async {
    final l = context.read<L10n>();
    final cleanUrl = cleanFileUrl(url);
    final ext = name.split('.').last.toLowerCase();

    final imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp'};
    if (imageExts.contains(ext)) {
      showImageViewer(ctx, cleanUrl, name);
      return;
    }

    var progress = 0.0;
    var cancelled = false;
    var dialogClosed = false;
    final cancelToken = CancelToken();
    StateSetter? setDialog;
    showCupertinoDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(builder: (dCtx, setD) {
        setDialog = setD;
        return CupertinoAlertDialog(
          title: Text(l.t('opening_file')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Text(name, style: const TextStyle(fontSize: 12, color: C.text4), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress > 0 ? progress : null, color: Theme.of(context).colorScheme.primary, backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12), minHeight: 5),
            ),
            const SizedBox(height: 6),
            Text(progress > 0 ? '${(progress * 100).toInt()}%' : l.t('downloading'), style: const TextStyle(fontSize: 12, color: C.text4)),
          ]),
          actions: [
            CupertinoDialogAction(
              onPressed: () {
                cancelled = true;
                dialogClosed = true;
                cancelToken.cancel('user_cancelled');
                Navigator.pop(dCtx);
              },
              child: Text(l.t('cancel')),
            ),
          ],
        );
      }),
    );

    try {
      final dir = await getTemporaryDirectory();
      final safeFileName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final filePath = '${dir.path}/${fileCacheKey(cleanUrl)}_$safeFileName';
      final file = File(filePath);

      if (!await file.exists()) {
        if (!mounted || cancelled) return;
        final api = context.read<ApiService>();
        await api.dio.download(
          cleanUrl,
          filePath,
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              progress = received / total;
              if (!dialogClosed) setDialog?.call(() {});
            }
          },
          options: Options(receiveTimeout: const Duration(minutes: 5)),
        );
      }

      if (!mounted || cancelled) return;
      dialogClosed = true;
      Navigator.pop(context);

      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done && mounted) {
        await launchUrl(Uri.parse(cleanUrl), mode: LaunchMode.externalApplication);
      }
    } on DioException catch (e) {
      if (!mounted || cancelled) return;
      dialogClosed = true;
      Navigator.pop(context);
      final code = e.response?.statusCode;
      if (code == 404) {
        showToast(context, l.t('file_not_found_server'), error: true);
        return;
      }
      // 403 = подпись истекла; в браузере юзер увидит сырой JSON, поэтому говорим честно.
      if (code == 403) {
        showToast(context, l.t('file_link_expired'), error: true);
        return;
      }
      try { await launchUrl(Uri.parse(cleanUrl), mode: LaunchMode.externalApplication); } catch (_) {}
    } catch (_) {
      if (!mounted || cancelled) return;
      dialogClosed = true;
      Navigator.pop(context);
      try { await launchUrl(Uri.parse(cleanUrl), mode: LaunchMode.externalApplication); } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final auth = context.watch<AuthProvider>();
    final meta = _meta;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = Theme.of(context).colorScheme.surface;

    final clsData = context.read<ClassesProvider>().allClasses
        .firstWhere((c) => c['id'] == widget.classId, orElse: () => <String, dynamic>{});

    final isArchivedForUser =
        (meta['is_archived_for_user'] == true) || (clsData['is_archived_for_user'] == true);
    final viewOnly = isArchivedForUser && !auth.isTeacher;

    final rawCoverImg = meta['cover_image'] ?? clsData['cover_image'];
    final coverImg = (rawCoverImg != null && !rawCoverImg.toString().startsWith('data:'))
        ? context.read<ApiService>().fixUrl(rawCoverImg.toString())
        : rawCoverImg;
    final displayTitle = (_title.isNotEmpty ? _title : (clsData['title'] ?? '')).toString();
    final displayDesc = (meta['description'] ?? clsData['description'] ?? '').toString();

    final inviteCode = (meta['invite_code'] as String?) ?? '';
    final headerSig = '$displayTitle|$displayDesc|${coverImg?.toString() ?? ''}|'
        '${auth.isTeacher}|$inviteCode|$isArchivedForUser|${l.t('class_code')}|${l.t('code_copied')}|${l.t('archived_badge')}|${l.t('regenerate_code')}';
    if (headerSig != _headerSig || _headerCache == null) {
      _headerSig = headerSig;
      _headerCache = ClassCoverSliver(
        classId: widget.classId,
        title: displayTitle,
        desc: displayDesc,
        coverImg: coverImg,
        isTeacher: auth.isTeacher,
        inviteCode: inviteCode,
        isArchived: isArchivedForUser,
        archivedLabel: l.t('archived_badge'),
        codeLabel: l.t('class_code'),
        codeCopiedLabel: l.t('code_copied'),
        onBack: () => Navigator.pop(context),
        onEdit: _editClass,
        regenerateLabel: l.t('regenerate_code'),
        onRegenerateCode: _regenerateCode,
      );
    }

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          _headerCache!,
        ],
        body: Column(children: [
          Container(
            decoration: BoxDecoration(
              color: surfaceColor,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05), blurRadius: 8, offset: const Offset(0, 2))],
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
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.1),
                unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                tabs: [
                  _tabItem(CupertinoIcons.book, '${l.t('lectures')} (${_lectures.length})'),
                  _tabItem(CupertinoIcons.square_stack_3d_down_right, l.t('materials')),
                  _tabItem(CupertinoIcons.list_bullet, l.t('assignments')),
                  _tabItem(CupertinoIcons.sparkles, l.t('ai_chat')),
                  _tabItem(CupertinoIcons.person_crop_rectangle,
                    _avatarLectureCount != null ? '${l.t('avatar')} ($_avatarLectureCount)' : l.t('avatar')),
                ],
              ),
              if (_canManageCohorts && _cohorts.length > 1) _cohortSelector(l),
              if (auth.isTeacher) AnimatedBuilder(animation: _tabCtrl, builder: (ctx, _) {
                if (_tabCtrl.index == 3 || _tabCtrl.index == 4) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Row(children: [
                    Expanded(child: GestureDetector(
                      onTap: () => _createAssignment(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.tile), border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.28))),
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
                        decoration: BoxDecoration(gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary]), borderRadius: BorderRadius.circular(AppRadii.tile), boxShadow: primaryGlow(Theme.of(context).colorScheme.primary, opacity: 0.28)),
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
          Expanded(child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: const [
                  SkeletonBox(width: 160, height: 18, borderRadius: 8),
                  SizedBox(height: 16),
                  SkeletonBox(width: double.infinity, height: 92, borderRadius: 16),
                  SizedBox(height: 12),
                  SkeletonBox(width: double.infinity, height: 92, borderRadius: 16),
                  SizedBox(height: 12),
                  SkeletonBox(width: double.infinity, height: 92, borderRadius: 16),
                ],
              )
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
                  viewOnly: viewOnly, cohortId: auth.isTeacher ? _selectedCohortId : null,
                  onRefresh: _loadAssignments, onEditAssignment: _editAssignment,
                  onOpenFile: (url, name) => _openFileViewer(context, url, name),
                ),
                _aiTab(viewOnly),
                ClassAvatarTab(
                  classId: widget.classId,
                  isTeacher: auth.isTeacher,
                  isActive: _avatarTabActive,
                  onLecturesChanged: (count) {
                    if (mounted && _avatarLectureCount != count) setState(() => _avatarLectureCount = count);
                  },
                ),
              ]),
          ),
        ]),
      ),
      floatingActionButton: null,
    );
  }

  void _editPost(dynamic p) {
    final l = context.read<L10n>();
    final tc = TextEditingController(text: cleanPostTitle(p['title'] ?? ''));
    final cc = TextEditingController(text: (() { try { return jsonDecode(p['body'])['content'] ?? ''; } catch (_) { return p['body'] ?? ''; } })());
    final Map<String, dynamic> existingBody = (() { try { return jsonDecode(p['body']) as Map<String, dynamic>; } catch (_) { return <String, dynamic>{}; } })();
    final List<dynamic> existingFiles = existingBody['files'] is List ? existingBody['files'] as List : [];

    final List<dynamic> editFiles = List<dynamic>.from(existingFiles);

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Padding(padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20), Text(l.t('edit_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16), TextField(controller: tc, decoration: InputDecoration(labelText: l.t('title_label'))),
            const SizedBox(height: 12), TextField(controller: cc, decoration: InputDecoration(labelText: l.t('content_label')), maxLines: 5),
            if (editFiles.isNotEmpty) ...[
              const SizedBox(height: 16),
              Align(alignment: Alignment.centerLeft, child: Text(l.t('attached_files_edit'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.text3))),
              const SizedBox(height: 8),
              ...editFiles.map((f) {
                final name = fileDisplayName(f.toString());
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(AppRadii.chip)),
                  child: Row(children: [
                    Icon(CupertinoIcons.doc, size: 14, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(name, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary), overflow: TextOverflow.ellipsis)),
                    GestureDetector(onTap: () => setS(() => editFiles.remove(f)), child: const Icon(CupertinoIcons.xmark, size: 14, color: C.text4)),
                  ]),
                );
              }),
            ],
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
                if (result != null && mounted) {
                  final api = context.read<ApiService>();
                  for (final pf in result.files) {
                    if (pf.path != null) {
                      try {
                        final res = await api.uploadFile(pf.path!, pf.name);
                        final url = res['url'] ?? res['file_url'] ?? res['path'];
                        if (url != null) setS(() => editFiles.add('$url#${Uri.encodeComponent(pf.name)}'));
                      } catch (_) {}
                    }
                  }
                }
              },
              child: Container(padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3))),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(CupertinoIcons.paperclip, size: 16, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 6), Text(l.t('attach_files_action'), style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600))])),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text(l.t('cancel')))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(onPressed: () async {
                try {
                  final prefix = (p['title'] ?? '').startsWith('[LECTURE]') ? '[LECTURE][${widget.classId}] ' : '[HW][${widget.classId}] ';
                  await context.read<ApiService>().updatePost(p['id'], '$prefix${tc.text.trim()}', jsonEncode({
                    'content': cc.text,
                    if (editFiles.isNotEmpty) 'files': editFiles,
                  }));
                  if (!mounted || !ctx.mounted) return;
                  Navigator.pop(ctx); _load(); showToast(context, l.t('save_ok'));
                } catch (_) { if (mounted && ctx.mounted) showToast(context, l.t('error_generic'), error: true); }
              }, child: Text(l.t('save')))),
            ]),
          ])));
      })).then((_) { tc.dispose(); cc.dispose(); });
  }

  List<String> _extractFiles(dynamic p) {
    try {
      final b = jsonDecode(p['body'] ?? '');
      if (b['files'] is List && (b['files'] as List).isNotEmpty) {
        return (b['files'] as List).map((f) => context.read<ApiService>().fixUrl(f.toString())).toList();
      }
    } catch (_) {}
    final body = p['body'] ?? '';
    return extractFileUrls(body)
        .map((u) => context.read<ApiService>().fixUrl(u))
        .toList();
  }

  List<String> _extractFilesFromText(String text) {
    final api = context.read<ApiService>();
    final result = <String>[];
    final seen = <String>{};
    for (final m in mdFileRe.allMatches(text)) {
      var url = m.group(2)!;
      if (!url.contains('#')) url = '$url#${Uri.encodeComponent(m.group(1)!)}';
      url = api.fixUrl(url);
      if (seen.add(url.split('#').first)) result.add(url);
    }
    for (final m in fileUrlRe.allMatches(text.replaceAll(mdFileRe, ''))) {
      final url = api.fixUrl(m.group(0)!);
      if (seen.add(url.split('#').first)) result.add(url);
    }
    return result;
  }

  Widget _cohortSelector(L10n l) {
    final activeCohort = _cohorts.firstWhere(
      (c) => c['status'] == 'active',
      orElse: () => null,
    );
    final activeId = activeCohort != null ? (activeCohort['id'] as num).toInt() : null;
    final isViewingPast = _selectedCohortId != null && _selectedCohortId != activeId;
    final primary = Theme.of(context).colorScheme.primary;

    String labelFor(dynamic c) {
      final year = (c['academic_year'] ?? '').toString();
      final isActive = c['status'] == 'active';
      return isActive ? '$year · ${l.t('active_cohort')}' : year;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: isViewingPast
              ? primary.withValues(alpha: 0.10)
              : adaptiveSurface2(context),
          borderRadius: BorderRadius.circular(12),
          border: isViewingPast
              ? Border.all(color: primary.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(children: [
          Icon(CupertinoIcons.calendar, size: 15,
              color: isViewingPast ? primary : C.text4),
          const SizedBox(width: 8),
          Text('${l.t('select_cohort')}:',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                  color: isViewingPast ? primary : C.text4)),
          const SizedBox(width: 4),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                isExpanded: true,
                isDense: true,
                value: _selectedCohortId ?? activeId ?? (_cohorts.first['id'] as num).toInt(),
                icon: Icon(CupertinoIcons.chevron_down, size: 14,
                    color: isViewingPast ? primary : C.text4),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    color: adaptiveText1(context)),
                items: [
                  for (final c in _cohorts)
                    DropdownMenuItem<int?>(
                      value: (c['id'] as num).toInt(),
                      child: Text(labelFor(c), overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedCohortId = (v == activeId) ? null : v);
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _aiTab(bool viewOnly) {
    if (viewOnly) {
      final l = context.read<L10n>();
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.lock_circle, size: 44,
                  color: adaptiveText1(context).withValues(alpha: 0.4)),
              const SizedBox(height: 14),
              Text(l.t('ai_unavailable_archive'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                      color: adaptiveText1(context).withValues(alpha: 0.6))),
            ],
          ),
        ),
      );
    }
    return ClassAiTab(
      classId: widget.classId, className: _title, lectureContext: _cachedLectureContext,
      lectureImageUrls: _cachedLectureImageUrls, isActive: _aiTabActive,
      isTeacher: context.read<AuthProvider>().isTeacher,
    );
  }

  void _showPost(dynamic p, String type, int num) {
    String content = '';
    try { final b = jsonDecode(p['body']); content = b['content'] ?? b['description'] ?? ''; }
    catch (_) { content = p['body'] ?? ''; }
    final files    = _extractFiles(p);
    final cleanText = cleanContent(content);
    final isLecture = type == 'lecture';
    final accent    = Theme.of(context).colorScheme.primary;
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final l         = context.read<L10n>();

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
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF006475), Theme.of(context).colorScheme.primary],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Center(child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(2)),
                  ))),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.18), shape: BoxShape.circle),
                      child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 16),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '${(isLecture ? l.t('lecture') : l.t('material')).toUpperCase()} $num',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1.0),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  cleanPostTitle(p['title'] ?? ''),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, height: 1.25, letterSpacing: -0.3),
                  maxLines: 3, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(CupertinoIcons.calendar, size: 12, color: Colors.white60),
                  const SizedBox(width: 5),
                  Text(fmtDate(p['created_at'] ?? ''), style: const TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w500)),
                  if (files.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.white30, shape: BoxShape.circle)),
                    const SizedBox(width: 12),
                    const Icon(CupertinoIcons.paperclip, size: 12, color: Colors.white60),
                    const SizedBox(width: 4),
                    Text('${files.length} ${files.length == 1 ? l.t('file') : l.t('files')}', style: const TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w500)),
                  ],
                ]),
              ]),
            ),

            Expanded(child: ListView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
              children: [
                if (cleanText.isNotEmpty) ...[
                  Row(children: [
                    Container(width: 3, height: 18, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 10),
                    Text(l.t('content_label'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: accent, letterSpacing: 0.3)),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? C.darkSurface2 : C.bg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accent.withValues(alpha: 0.1)),
                    ),
                    child: Text(cleanText, style: const TextStyle(fontSize: 15, height: 1.75, letterSpacing: 0.1)),
                  ),
                  const SizedBox(height: 24),
                ],

                if (files.isNotEmpty) ...[
                  Row(children: [
                    Container(width: 3, height: 18, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 10),
                    Text(l.t('attached_files_edit'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: accent, letterSpacing: 0.3)),
                  ]),
                  const SizedBox(height: 12),
                  ...files.asMap().entries.map((entry) {
                    final i = entry.key; final f = entry.value;
                    final name = fileDisplayName(f);
                    final ext  = name.split('.').last.toLowerCase();

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
                            border: Border.all(color: fileColor.withValues(alpha: 0.18)),
                            boxShadow: [BoxShadow(color: fileColor.withValues(alpha: isDark ? 0.04 : 0.07), blurRadius: 10, offset: const Offset(0, 3))],
                          ),
                          child: Row(children: [
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
                              Text(l.t('tap_to_open'), style: const TextStyle(fontSize: 11, color: C.text4)),
                            ])),
                            Container(
                              width: 34, height: 34,
                              decoration: BoxDecoration(color: fileColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadii.chip)),
                              child: Icon(CupertinoIcons.arrow_up_right_square, size: 16, color: fileColor),
                            ),
                          ]),
                        ),
                      ),
                    );
                  }),
                ],

                if (cleanText.isEmpty && files.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 64, height: 64,
                        decoration: BoxDecoration(color: accent.withValues(alpha: 0.08), shape: BoxShape.circle),
                        child: Icon(isLecture ? CupertinoIcons.book : CupertinoIcons.tray, size: 30, color: accent)),
                      const SizedBox(height: 14),
                      Text(l.t('content_empty'), style: const TextStyle(fontSize: 14, color: C.text4, fontWeight: FontWeight.w500)),
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

  void _showAddMenu() {
    final l = context.read<L10n>();
    String type = 'lecture';
    final tc = TextEditingController(), cc = TextEditingController();
    List<PlatformFile> lectureFiles = [];
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadii.tile)),
              child: Icon(CupertinoIcons.book, color: Theme.of(context).colorScheme.primary, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.t('add_lecture'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(l.t('add_sub'), style: const TextStyle(fontSize: 12, color: C.text4)),
            ])),
            IconButton(icon: const Icon(CupertinoIcons.xmark), onPressed: () => Navigator.pop(ctx)),
          ]),
          const SizedBox(height: 20),
          Container(decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(AppRadii.tile)),
            child: Row(children: [
              Expanded(child: GestureDetector(onTap: () => setS(() => type = 'lecture'),
                child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: type == 'lecture' ? Theme.of(ctx).colorScheme.surface : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(CupertinoIcons.book, size: 16, color: type == 'lecture' ? Theme.of(context).colorScheme.primary : C.text4), const SizedBox(width: 6), Text(l.t('lecture'), style: TextStyle(fontWeight: FontWeight.w600, color: type == 'lecture' ? Theme.of(context).colorScheme.primary : C.text4))])))),
              Expanded(child: GestureDetector(onTap: () => setS(() => type = 'material'),
                child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: type == 'material' ? Theme.of(ctx).colorScheme.surface : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(CupertinoIcons.doc_text, size: 16, color: type == 'material' ? Theme.of(context).colorScheme.primary : C.text4), const SizedBox(width: 6), Text(l.t('material'), style: TextStyle(fontWeight: FontWeight.w600, color: type == 'material' ? Theme.of(context).colorScheme.primary : C.text4))])))),
            ])),
          const SizedBox(height: 20),
          _fieldLabel2('${type == 'lecture' ? l.t('lecture_topic') : l.t('material_topic')} *'),
          TextField(controller: tc, decoration: InputDecoration(hintText: l.t('topic_hint'))),
          const SizedBox(height: 16),
          _fieldLabel2(type == 'lecture' ? l.t('lecture_content') : l.t('material_content')),
          TextField(controller: cc, decoration: InputDecoration(hintText: l.t('content_body_hint')), maxLines: 4),
          const SizedBox(height: 20),
          _fieldLabel2(l.t('attach_files')),
          GestureDetector(onTap: () async {
            final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
            if (result != null) setS(() => lectureFiles.addAll(result.files));
          }, child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.tile), border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3))),
            child: Column(children: [
              Icon(CupertinoIcons.arrow_up_doc, size: 24, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 6),
              Text(l.t('click_or_choose'), style: const TextStyle(fontSize: 13, color: C.text4)),
              Text(l.t('file_types_hint'), style: const TextStyle(fontSize: 10, color: C.text4)),
            ]))),
          if (lectureFiles.isNotEmpty) ...[const SizedBox(height: 8),
            ...lectureFiles.map((f) => Container(margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(AppRadii.chip)),
              child: Row(children: [Icon(CupertinoIcons.doc_text, size: 14, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 6), Expanded(child: Text(f.name, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary), overflow: TextOverflow.ellipsis)), GestureDetector(onTap: () => setS(() => lectureFiles.remove(f)), child: const Icon(CupertinoIcons.xmark, size: 14, color: C.text4))])))],
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)), child: Text(l.t('cancel')))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(icon: const Icon(CupertinoIcons.plus, size: 16, color: Colors.white), label: Text(l.t('publish')),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
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
                        if (url != null) fileUrls.add('$url#${Uri.encodeComponent(pf.name)}');
                      } catch (_) {}
                    }
                  }
                  await api.createPost('$prefix ${tc.text.trim()}', jsonEncode({
                    'content': cc.text,
                    if (fileUrls.isNotEmpty) 'files': fileUrls,
                  }));
                  if (!mounted || !ctx.mounted) return;
                  Navigator.pop(ctx); _load(); showToast(context, l.t('published'));
                } catch (_) { if (mounted && ctx.mounted) showToast(context, l.t('error_generic'), error: true); }
              })),
          ]),
        ])))).then((_) { tc.dispose(); cc.dispose(); });
  }

  void _createAssignment() {
    final l = context.read<L10n>();
    final tc = TextEditingController(), dc = TextEditingController(), sc = TextEditingController(text: '100');
    DateTime? deadline;
    List<Map<String, dynamic>> criteria = [{'name': '', 'weight': 100, 'desc': ''}];
    List<PlatformFile> attachedFiles = [];
    List<PlatformFile> referenceFiles = [];

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(expand: false, initialChildSize: 0.9, maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.all(24), children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppRadii.tile)),
              child: Icon(CupertinoIcons.pencil, color: Theme.of(context).colorScheme.primary, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.t('new_assignment'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(l.t('fill_assignment'), style: const TextStyle(fontSize: 12, color: C.text4)),
            ])),
            IconButton(icon: const Icon(CupertinoIcons.xmark), onPressed: () => Navigator.pop(ctx)),
          ]),
          const SizedBox(height: 24),
          _fieldLabel2('${l.t('assignment_title')} *'),
          TextField(controller: tc, decoration: InputDecoration(hintText: l.t('assignment_title_hint'))),
          const SizedBox(height: 16),
          _fieldLabel2(l.t('assignment_desc')),
          TextField(controller: dc, decoration: InputDecoration(hintText: l.t('assignment_desc_hint')), maxLines: 4),
          const SizedBox(height: 16),
          _fieldLabel2(l.t('max_score')),
          TextField(controller: sc, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: '100')),
          const SizedBox(height: 16),
          _fieldLabel2(l.t('deadline')),
          GestureDetector(onTap: () async {
            final d = await showDatePicker(context: ctx, initialDate: DateTime.now().add(const Duration(days: 7)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
            if (d != null && ctx.mounted) {
              final t = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 23, minute: 59));
              setS(() => deadline = DateTime(d.year, d.month, d.day, t?.hour ?? 23, t?.minute ?? 59));
            }
          }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(AppRadii.tile)),
            child: Row(children: [
              Text(deadline != null ? '${deadline!.day.toString().padLeft(2, '0')}.${deadline!.month.toString().padLeft(2, '0')}.${deadline!.year} ${deadline!.hour.toString().padLeft(2, '0')}:${deadline!.minute.toString().padLeft(2, '0')}' : l.t('deadline_placeholder'), style: TextStyle(fontSize: 14, color: deadline != null ? null : C.text4)),
              const Spacer(), const Icon(CupertinoIcons.calendar, size: 18, color: C.text4),
            ]))),
          const SizedBox(height: 20),
          Row(children: [
            Text(l.t('attached_files'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1)),
            const Spacer(),
            GestureDetector(
              onTap: () async {
                final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
                if (result != null) setS(() => attachedFiles.addAll(result.files));
              },
              child: Text('+ ${l.t('add')}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
            ),
          ]),
          const SizedBox(height: 8),
          if (attachedFiles.isEmpty)
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [const Icon(CupertinoIcons.paperclip, size: 16, color: C.text4), const SizedBox(width: 8), Text(l.t('no_attached_files'), style: const TextStyle(fontSize: 13, color: C.text4))]))
          else
            ...attachedFiles.map((f) => Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(CupertinoIcons.doc, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(f.name, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: () => setS(() => attachedFiles.removeWhere((x) => x.name == f.name)),
                  child: const Icon(CupertinoIcons.xmark, size: 14, color: C.text4)),
              ]))),
          const SizedBox(height: 20),
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 36, height: 36, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadii.chip)),
                  child: Icon(CupertinoIcons.checkmark_circle, size: 18, color: Theme.of(context).colorScheme.primary)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Text(l.t('reference_solutions'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)), const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Text(l.t('graded_by_ai'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)))]),
                  Text(l.t('reference_sub'), style: const TextStyle(fontSize: 11, color: C.text4)),
                ])),
              ]),
              const SizedBox(height: 12),
              GestureDetector(onTap: () async {
                final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
                if (result != null) setS(() => referenceFiles.addAll(result.files));
              },
              child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.tile), border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3))),
                child: Column(children: [
                  Icon(CupertinoIcons.arrow_up_doc, size: 28, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 6),
                  Text(l.t('click_or_choose'), style: const TextStyle(fontSize: 13, color: C.text4)),
                  const Text('PDF, DOCX, DOC, PPTX, XLSX, TXT, MD', style: TextStyle(fontSize: 10, color: C.text4)),
                ]))),
              if (referenceFiles.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...referenceFiles.map((f) => Container(margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(AppRadii.chip)),
                  child: Row(children: [Icon(CupertinoIcons.doc_text, size: 14, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 6), Expanded(child: Text(f.name, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary), overflow: TextOverflow.ellipsis)), GestureDetector(onTap: () => setS(() => referenceFiles.remove(f)), child: const Icon(CupertinoIcons.xmark, size: 14, color: C.text4))]))),
              ],
            ])),
          const SizedBox(height: 20),
          Row(children: [
            Text(l.t('grading_criteria'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1)),
            const Spacer(),
            GestureDetector(onTap: () => setS(() => criteria.add({'name': '', 'weight': 0, 'desc': ''})),
              child: Text('+ ${l.t('add')}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary))),
          ]),
          const SizedBox(height: 4),
          Text('${l.t('criteria_sum_hint')} (${sc.text}/${sc.text})', style: const TextStyle(fontSize: 11, color: C.text4)),
          const SizedBox(height: 12),
          ...List.generate(criteria.length, (i) {
            final nameC = TextEditingController(text: criteria[i]['name']);
            final weightC = TextEditingController(text: '${criteria[i]['weight']}');
            final descC = TextEditingController(text: criteria[i]['desc'] ?? '');
            return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(AppRadii.tile)),
              child: Column(children: [
                Row(children: [
                  Text('${i + 1}', style: const TextStyle(fontSize: 12, color: C.text4)),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: nameC, decoration: InputDecoration(hintText: l.t('criterion_name'), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)), onChanged: (v) => criteria[i]['name'] = v)),
                  const SizedBox(width: 8),
                  SizedBox(width: 60, child: TextField(controller: weightC, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(vertical: 10)), onChanged: (v) => criteria[i]['weight'] = int.tryParse(v) ?? 0)),
                  const SizedBox(width: 4),
                  GestureDetector(onTap: () { if (criteria.length > 1) setS(() => criteria.removeAt(i)); }, child: const Icon(CupertinoIcons.xmark, size: 16, color: C.red)),
                ]),
                const SizedBox(height: 6),
                TextField(controller: descC, decoration: InputDecoration(hintText: l.t('criterion_desc'), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)), onChanged: (v) => criteria[i]['desc'] = v),
              ]));
          }),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)), child: Text(l.t('cancel')))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(icon: const Icon(CupertinoIcons.plus, size: 16, color: Colors.white), label: Text(l.t('create_assignment')),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                if (tc.text.trim().isEmpty) return;
                try {
                  final api = context.read<ApiService>();

                  final fileUrls = <String>[];
                  for (final pf in [...attachedFiles, ...referenceFiles]) {
                    if (pf.path != null) {
                      try {
                        final res = await api.uploadFile(pf.path!, pf.name);
                        final url = res['url'] ?? res['file_url'] ?? res['path'];
                        if (url != null && url.toString().isNotEmpty) {
                          fileUrls.add('$url#${Uri.encodeComponent(pf.name)}');
                        }
                      } catch (e) {
                        if (mounted) showToast(context, '${l.t('upload_error')}: ${pf.name}', error: true);
                      }
                    }
                  }

                  if (!mounted) return;
                  final fixedUrls = fileUrls.map(context.read<ApiService>().fixUrl).toList();

                  final baseDesc = dc.text.trim();
                  final descWithFiles = fixedUrls.isEmpty
                      ? baseDesc
                      : baseDesc.isEmpty
                          ? fixedUrls.join('\n')
                          : '$baseDesc\n${fixedUrls.join('\n')}';

                  final maxScore = int.tryParse(sc.text) ?? 100;
                  final filteredCriteria = criteria.where((c) => c['name'].toString().isNotEmpty).toList();
                  final finalCriteria = filteredCriteria.isEmpty
                      ? [{'name': l.t('default_criterion'), 'weight': maxScore, 'description': ''}]
                      : filteredCriteria.map((c) => {'name': c['name'], 'weight': c['weight'], 'description': c['desc']}).toList();

                  await api.createAssignment({
                    'class_id': widget.classId,
                    'title': tc.text.trim(),
                    'description': descWithFiles,
                    'max_score': maxScore,
                    'criteria': finalCriteria,
                    if (deadline != null) 'deadline': deadline!.toIso8601String(),
                  });

                  if (!mounted || !ctx.mounted) return;
                  Navigator.pop(ctx);
                  _loadAssignments();
                  showToast(context, fileUrls.isNotEmpty
                      ? '${l.t('assignment_created')} (${fileUrls.length} ${l.t('file')})'
                      : l.t('assignment_created'));
                } catch (e) {
                  if (mounted && ctx.mounted) showToast(context, '${l.t('error_generic')}: $e', error: true);
                }
              })),
          ]),
          const SizedBox(height: 24),
        ])))).then((_) { tc.dispose(); dc.dispose(); sc.dispose(); });
  }

  Widget _fieldLabel2(String s) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(s, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1)));

  void _editAssignment(dynamic a) {
    final l = context.read<L10n>();
    final rawDesc = a['description']?.toString() ?? '';
    final tc = TextEditingController(text: a['title'] ?? '');
    final dc = TextEditingController(text: cleanContent(rawDesc));
    final sc = TextEditingController(text: '${a['max_score'] ?? 100}');
    DateTime? deadline;
    try { if (a['deadline'] != null) deadline = DateTime.parse(a['deadline']); } catch (_) {}

    final existingUrls = _extractFilesFromText(rawDesc);
    List<String> keepUrls = List<String>.from(existingUrls);
    List<PlatformFile> newFiles = [];

    List<Map<String, dynamic>> criteria = [];
    try {
      final raw = jsonDecode(a['criteria'] ?? '[]');
      criteria = (raw as List).map((c) => {'name': c['name'] ?? '', 'weight': c['weight'] ?? 0, 'desc': c['description'] ?? c['desc'] ?? ''}).toList();
    } catch (_) {}
    if (criteria.isEmpty) criteria = [{'name': '', 'weight': a['max_score'] ?? 100, 'desc': ''}];

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.9, maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.all(24), children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppRadii.tile)),
              child: const Icon(CupertinoIcons.pencil, color: Color(0xFFF59E0B), size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.t('edit_assignment'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text(a['title'] ?? '', style: const TextStyle(fontSize: 12, color: C.text4), overflow: TextOverflow.ellipsis),
            ])),
            IconButton(icon: const Icon(CupertinoIcons.xmark), onPressed: () => Navigator.pop(ctx)),
          ]),
          const SizedBox(height: 24),
          _fieldLabel2('${l.t('class_name')} *'),
          TextField(controller: tc, decoration: InputDecoration(hintText: l.t('assignment_name_hint'))),
          const SizedBox(height: 16),
          _fieldLabel2(l.t('assignment_desc')),
          TextField(controller: dc, decoration: InputDecoration(hintText: l.t('assignment_desc_hint')), maxLines: 4),
          const SizedBox(height: 16),
          _fieldLabel2(l.t('max_score')),
          TextField(controller: sc, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: '100')),
          const SizedBox(height: 16),
          _fieldLabel2(l.t('deadline')),
          GestureDetector(onTap: () async {
            final d = await showDatePicker(context: ctx, initialDate: deadline ?? DateTime.now().add(const Duration(days: 7)), firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)));
            if (d != null && ctx.mounted) {
              final t = await showTimePicker(context: ctx, initialTime: TimeOfDay(hour: deadline?.hour ?? 23, minute: deadline?.minute ?? 59));
              setS(() => deadline = DateTime(d.year, d.month, d.day, t?.hour ?? 23, t?.minute ?? 59));
            }
          }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(AppRadii.tile)),
            child: Row(children: [
              Text(deadline != null ? '${deadline!.day.toString().padLeft(2,'0')}.${deadline!.month.toString().padLeft(2,'0')}.${deadline!.year} ${deadline!.hour.toString().padLeft(2,'0')}:${deadline!.minute.toString().padLeft(2,'0')}' : l.t('deadline_placeholder'), style: TextStyle(fontSize: 14, color: deadline != null ? null : C.text4)),
              const Spacer(), const Icon(CupertinoIcons.calendar, size: 18, color: C.text4),
            ]))),
          const SizedBox(height: 20),
          if (keepUrls.isNotEmpty) ...[
            Row(children: [
              Text(l.t('current_files'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1)),
              const Spacer(),
              Text(l.t('tap_x_remove'), style: const TextStyle(fontSize: 11, color: C.text4)),
            ]),
            const SizedBox(height: 8),
            ...keepUrls.map((url) {
              final name = fileDisplayName(url);
              return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(CupertinoIcons.doc, size: 15, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8),
                  Expanded(child: Text(name, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary), overflow: TextOverflow.ellipsis)),
                  GestureDetector(onTap: () => setS(() => keepUrls.remove(url)), child: const Icon(CupertinoIcons.xmark, size: 15, color: C.red)),
                ]));
            }),
            const SizedBox(height: 12),
          ],
          Row(children: [
            Text(l.t('add_files_label'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1)),
            const Spacer(),
            GestureDetector(
              onTap: () async {
                final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
                if (r != null) setS(() => newFiles.addAll(r.files));
              },
              child: Text('+ ${l.t('add')}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
            ),
          ]),
          const SizedBox(height: 8),
          if (newFiles.isNotEmpty) ...newFiles.map((f) => Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(CupertinoIcons.doc, size: 15, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8),
              Expanded(child: Text(f.name, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary), overflow: TextOverflow.ellipsis)),
              GestureDetector(onTap: () => setS(() => newFiles.remove(f)), child: const Icon(CupertinoIcons.xmark, size: 15, color: C.text4)),
            ])))
          else Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [const Icon(CupertinoIcons.paperclip, size: 15, color: C.text4), const SizedBox(width: 8), Text(l.t('no_new_files'), style: const TextStyle(fontSize: 13, color: C.text4))])),
          const SizedBox(height: 24),
          Row(children: [
            Text(l.t('grading_criteria'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1)),
            const Spacer(),
            GestureDetector(onTap: () => setS(() => criteria.add({'name': '', 'weight': 0, 'desc': ''})),
              child: Text('+ ${l.t('add')}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary))),
          ]),
          const SizedBox(height: 12),
          ...List.generate(criteria.length, (i) {
            final nameC   = TextEditingController(text: criteria[i]['name']);
            final weightC = TextEditingController(text: '${criteria[i]['weight']}');
            final descC   = TextEditingController(text: criteria[i]['desc'] ?? '');
            return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(AppRadii.tile)),
              child: Column(children: [
                Row(children: [
                  Text('${i+1}', style: const TextStyle(fontSize: 12, color: C.text4)), const SizedBox(width: 8),
                  Expanded(child: TextField(controller: nameC, decoration: InputDecoration(hintText: l.t('criterion_short'), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)), onChanged: (v) => criteria[i]['name'] = v)),
                  const SizedBox(width: 8),
                  SizedBox(width: 60, child: TextField(controller: weightC, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(vertical: 10)), onChanged: (v) => criteria[i]['weight'] = int.tryParse(v) ?? 0)),
                  const SizedBox(width: 4),
                  GestureDetector(onTap: () { if (criteria.length > 1) setS(() => criteria.removeAt(i)); }, child: const Icon(CupertinoIcons.xmark, size: 16, color: C.red)),
                ]),
                const SizedBox(height: 6),
                TextField(controller: descC, decoration: InputDecoration(hintText: l.t('criterion_desc'), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)), onChanged: (v) => criteria[i]['desc'] = v),
              ]));
          }),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => _showVariantsSheet((a['id'] as num).toInt()),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.tile)),
              child: Row(children: [
                Icon(CupertinoIcons.square_stack, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(context.read<L10n>().t('assignment_variants'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                const Icon(CupertinoIcons.chevron_right, size: 16, color: C.text4),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)), child: Text(l.t('cancel')))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(
              icon: const Icon(CupertinoIcons.checkmark, size: 16, color: Colors.white),
              label: Text(l.t('save')),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
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
                        if (url != null) uploadedUrls.add('$url#${Uri.encodeComponent(pf.name)}');
                      } catch (_) {}
                    }
                  }
                  if (!mounted) return;
                  final fixedNewUrls = uploadedUrls.map(context.read<ApiService>().fixUrl).toList();
                  final fixedKeepUrls = keepUrls.map(context.read<ApiService>().fixUrl).toList();
                  final allUrls = [...fixedKeepUrls, ...fixedNewUrls];

                  final cleanDesc = cleanContent(dc.text.trim());
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
                  if (!mounted || !ctx.mounted) return;
                  Navigator.pop(ctx); _loadAssignments(); showToast(context, l.t('updated'));
                } catch (e) { if (mounted && ctx.mounted) showToast(context, '${l.t('error_generic')}: $e', error: true); }
              },
            )),
          ]),
          const SizedBox(height: 24),
        ]),
      )),
    ).then((_) { tc.dispose(); dc.dispose(); sc.dispose(); });
  }

  void _showVariantsSheet(int assignmentId) {
    final l = context.read<L10n>();
    List<dynamic>? variants;
    bool adding = false;
    final variantTitleC = TextEditingController();
    final variantContentC = TextEditingController();
    bool loadTriggered = false;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Future<void> load() async {
          try {
            final v = await context.read<ApiService>().getAssignmentVariants(assignmentId);
            if (ctx.mounted) setS(() { variants = v; });
          } catch (_) {
            if (ctx.mounted) setS(() { variants = []; });
          }
        }
        if (!loadTriggered) { loadTriggered = true; load(); }

        return DraggableScrollableSheet(expand: false, initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.4,
          builder: (ctx, scroll) => Column(children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
              Expanded(child: Text(l.t('assignment_variants'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              IconButton(icon: const Icon(CupertinoIcons.xmark), onPressed: () => Navigator.pop(ctx)),
            ])),
            Expanded(child: variants == null
                ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
                : ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
                    TextField(controller: variantTitleC, decoration: InputDecoration(hintText: l.t('variant_title_hint'))),
                    const SizedBox(height: 8),
                    TextField(controller: variantContentC, decoration: InputDecoration(hintText: l.t('variant_content_hint')), maxLines: 3),
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: ElevatedButton.icon(
                      onPressed: adding ? null : () async {
                        if (variantTitleC.text.trim().isEmpty) return;
                        setS(() => adding = true);
                        try {
                          await context.read<ApiService>().createAssignmentVariant(assignmentId, {
                            'title': variantTitleC.text.trim(),
                            'content': variantContentC.text.trim(),
                          });
                          if (!ctx.mounted) return;
                          variantTitleC.clear(); variantContentC.clear();
                          setS(() => adding = false);
                          await load();
                        } catch (_) {
                          if (ctx.mounted) setS(() => adding = false);
                          if (mounted && ctx.mounted) showToast(context, l.t('error'), error: true);
                        }
                      },
                      icon: adding
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(CupertinoIcons.add, size: 16, color: Colors.white),
                      label: Text(l.t('assignment_variants_add')),
                    )),
                    const SizedBox(height: 20),
                    if (variants!.isEmpty)
                      Padding(padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text(l.t('assignment_variants_empty'), style: const TextStyle(color: C.text4))))
                    else
                      ...variants!.map((v) {
                        final vid = (v['id'] as num?)?.toInt();
                        return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.tile)),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text((v['title'] ?? '').toString(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                              if ((v['content'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
                                child: Text((v['content'] ?? '').toString(), style: const TextStyle(fontSize: 12, color: C.text4), maxLines: 3, overflow: TextOverflow.ellipsis)),
                            ])),
                            GestureDetector(
                              onTap: () async {
                                if (vid == null) return;
                                final ok = await showConfirmDialog(context,
                                  title: l.t('variant_delete_confirm'),
                                  icon: CupertinoIcons.trash,
                                  danger: true,
                                  confirmText: l.t('delete'),
                                  cancelText: l.t('cancel'));
                                if (ok != true || !mounted || !ctx.mounted) return;
                                try {
                                  await context.read<ApiService>().deleteAssignmentVariant(assignmentId, vid);
                                  if (ctx.mounted) await load();
                                } catch (_) {
                                  if (mounted && ctx.mounted) showToast(context, l.t('error'), error: true);
                                }
                              },
                              child: const Padding(padding: EdgeInsets.all(4), child: Icon(CupertinoIcons.trash, size: 16, color: C.red)),
                            ),
                          ]));
                      }),
                  ])),
          ]));
      }),
    ).then((_) { variantTitleC.dispose(); variantContentC.dispose(); });
  }

  Future<void> _regenerateCode() async {
    final l = context.read<L10n>();
    final ok = await showConfirmDialog(context,
      title: l.t('regenerate_code_confirm'),
      icon: CupertinoIcons.refresh,
      confirmText: l.t('regenerate_code'),
      cancelText: l.t('cancel'));
    if (ok != true || !mounted) return;
    try {
      final newCode = await context.read<ApiService>().regenerateInviteCode(widget.classId);
      if (!mounted) return;
      setState(() {
        _classData = {..._classData, 'invite_code': newCode};
        _meta = _classData;
      });
      showToast(context, '${l.t('regenerate_code_ok')}: $newCode');
    } catch (_) {
      if (mounted) showToast(context, l.t('error'), error: true);
    }
  }

  void _editClass() {
    final l = context.read<L10n>();
    final meta = _meta;
    final tc = TextEditingController(text: _title), dc = TextEditingController(text: meta['description'] ?? ''), tn = TextEditingController(text: meta['teacher'] ?? '');
    final String? existingCover = meta['cover_image'];
    XFile? newCoverFile;
    bool coverRemoved = false;
    bool saving = false;
    final bool rotationOriginal = (meta['rotation_mode'] == 'yearly');
    bool rotationYearly = rotationOriginal;

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(expand: false, initialChildSize: 0.85, maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.all(24), children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadii.tile)),
              child: Icon(CupertinoIcons.pencil, color: Theme.of(context).colorScheme.primary, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Text(l.t('edit_class'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            IconButton(icon: const Icon(CupertinoIcons.xmark), onPressed: () => Navigator.pop(ctx)),
          ]),
          const SizedBox(height: 24),
          _fieldLabel2(l.t('class_cover')),
          GestureDetector(
            onTap: () async {
              final picker = ImagePicker();
              final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1200);
              if (img == null) return;
              setS(() { newCoverFile = img; coverRemoved = false; });
            },
            child: Container(height: 150, decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3), width: 1.5)),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                if (newCoverFile != null)
                  Image.file(File(newCoverFile!.path), fit: BoxFit.cover)
                else if (!coverRemoved && existingCover != null && existingCover.startsWith('data:'))
                  Builder(builder: (_) {
                    final bytes = decodeBase64Image(existingCover);
                    return bytes != null ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true) : Container(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1));
                  })
                else if (!coverRemoved && existingCover != null)
                  CachedNetworkImage(imageUrl: context.read<ApiService>().fixUrl(existingCover), fit: BoxFit.cover, memCacheWidth: 800, fadeInDuration: Duration.zero, fadeOutDuration: Duration.zero, placeholder: (_, __) => const SizedBox.shrink(), errorWidget: (_, __, ___) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [const Color(0xFF006475), Theme.of(context).colorScheme.primary]))))
                else
                  Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [const Color(0xFF006475), Theme.of(context).colorScheme.primary], begin: Alignment.topLeft, end: Alignment.bottomRight))),
                Container(color: Colors.black.withValues(alpha: 0.3),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(CupertinoIcons.photo, color: Colors.white, size: 32),
                    const SizedBox(height: 6),
                    Text((newCoverFile != null || (!coverRemoved && existingCover != null)) ? l.t('click_to_replace') : l.t('choose_cover'), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  ])),
              ])),
          ),
          if (newCoverFile != null || (!coverRemoved && existingCover != null)) ...[
            const SizedBox(height: 8),
            GestureDetector(onTap: () => setS(() { newCoverFile = null; coverRemoved = true; }),
              child: Row(children: [const Icon(CupertinoIcons.xmark, size: 14, color: C.red), const SizedBox(width: 4), Text(l.t('remove_cover'), style: const TextStyle(fontSize: 12, color: C.red))])),
          ],
          const SizedBox(height: 20),
          _fieldLabel2('${l.t('class_name')} *'),
          TextField(controller: tc, decoration: InputDecoration(hintText: l.t('class_name_simple_hint'))),
          const SizedBox(height: 16),
          _fieldLabel2(l.t('class_desc')),
          TextField(controller: dc, decoration: InputDecoration(hintText: l.t('class_desc_simple_hint')), maxLines: 3),
          const SizedBox(height: 16),
          _fieldLabel2(l.t('teacher_name_label')),
          TextField(controller: tn, decoration: InputDecoration(hintText: l.t('teacher_display_hint'))),
          if (_canManageCohorts) ...[
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: adaptiveSurface2(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              value: rotationYearly,
              onChanged: saving ? null : (v) => setS(() => rotationYearly = v),
              title: Text(context.read<L10n>().t('yearly_rotation'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(context.read<L10n>().t('yearly_rotation_sub'),
                    style: const TextStyle(fontSize: 12.5, color: C.text4)),
              ),
            ),
          ),
          if (rotationYearly) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                Navigator.pop(ctx);
                final changed = await Navigator.push<bool>(context,
                    MaterialPageRoute(builder: (_) => const RolloverScreen()));
                if (changed == true && mounted) _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)),
                ),
                child: Row(children: [
                  Icon(CupertinoIcons.calendar_badge_plus, size: 19, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(context.read<L10n>().t('new_academic_year'),
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary))),
                  Icon(CupertinoIcons.chevron_right, size: 15, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)),
                ]),
              ),
            ),
          ],
          ],
          const SizedBox(height: 28),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: saving ? null : () => Navigator.pop(ctx), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)), child: Text(l.t('cancel')))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: saving ? null : () async {
                setS(() => saving = true);
                try {
                  final api = context.read<ApiService>();
                  final coverChanged = newCoverFile != null || coverRemoved;
                  String? coverImage;
                  if (newCoverFile != null) {
                    final res = await api.uploadFile(newCoverFile!.path, newCoverFile!.name);
                    coverImage = (res['url'] ?? res['file_url'] ?? res['path'])?.toString();
                  } else if (coverRemoved) {
                    coverImage = '';
                  } else if (existingCover != null) {
                    coverImage = existingCover;
                  }
                  final updated = await api.updateClass(widget.classId,
                      name: tc.text.trim(),
                      description: dc.text.trim(),
                      teacher: tn.text.trim(),
                      coverImage: coverImage);
                  if (rotationYearly != rotationOriginal) {
                    await api.setRotationMode(
                        widget.classId, rotationYearly ? 'yearly' : 'manual');
                  }
                  if (!mounted || !ctx.mounted) return;
                  if (coverChanged) await _evictCoverCache(coverImage);
                  if (!mounted || !ctx.mounted) return;
                  Navigator.pop(ctx);
                  _applyClassUpdate(updated);
                  showToast(context, l.t('class_updated'));
                } catch (_) {
                  if (mounted && ctx.mounted) { showToast(context, l.t('error_generic'), error: true); setS(() => saving = false); }
                }
              },
              child: saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(l.t('save')),
            )),
          ]),
          const SizedBox(height: 24),
        ])))).then((_) { tc.dispose(); dc.dispose(); tn.dispose(); });
  }

  @override void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }
}
