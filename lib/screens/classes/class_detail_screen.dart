import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart' show Options, CancelToken, DioException;
import '../../providers/auth_provider.dart';
import '../../providers/classes_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/cover_appearance.dart';
import '../../utils/cover_art.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/toast.dart';
import '../../widgets/tappable.dart';
import 'tabs/class_posts_tab.dart';
import 'tabs/class_assignments_tab.dart';
import 'tabs/class_ai_tab.dart';
import 'rollover_screen.dart';
import 'class_detail_utils.dart';
import 'widgets/class_cover_sliver.dart';
import 'lecture_detail_screen.dart';
import 'lecture_editor_screen.dart';
import 'assignment_editor_screen.dart';
import '../../utils/haptics.dart';
import '../../utils/nav_guard.dart';

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
  Map<String, dynamic> _classData = {};
  Map<String, dynamic> _meta = {};
  String _title = '';
  List<dynamic> _lectures = [];
  bool _loading = true, _loadingAsg = false, _aiTabActive = false;
  bool _coverPrecached = false;
  Widget? _headerCache;
  String _headerSig = '';
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
    _tabCtrl = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _aiTabActive = widget.initialTab == 2;
    _tabCtrl.addListener(() {
      if (_tabCtrl.index == 1 && _assignments.isEmpty) _loadAssignments();
      if (_tabCtrl.indexIsChanging) {
        hapticSelection();
      } else {
        final isAi = _tabCtrl.index == 2;
        if (_aiTabActive != isAi) {
          setState(() { _aiTabActive = isAi; });
        }
      }
    });
    _load();
    if (widget.initialTab == 1) _loadAssignments();
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
        // Ключ кэша — без query (exp/sig меняются при каждом ответе сервера,
        // см. NetworkCoverImage._stableCacheKey), иначе прекэш не совпадёт
        // с виджетом, который реально рисует обложку.
        final qIdx = url.indexOf('?');
        final cacheKey = qIdx == -1 ? url : url.substring(0, qIdx);
        precacheImage(
          ResizeImage(
            CachedNetworkImageProvider(url, cacheKey: cacheKey),
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
    if (_canManageCohorts) _loadCohorts();
  }

  // Обложки теперь кэшируются по самому URL (не по стабильному id-ключу) —
  // каждая новая загрузка обложки получает свой уникальный URL в облачном
  // хранилище, поэтому старые байты просто перестают запрашиваться. Явный
  // evict больше не нужен для попадания в другие вкладки, но подчищаем
  // live-кэш, чтобы не тянуть старый кадр до следующего кадра рендера.
  void _evictCoverCache() {
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
    _meta = _classData;
    _title = (_classData['name'] ?? '${context.read<L10n>().t('class_label')} #${widget.classId}').toString();
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

  /// Быстрое добавление (учитель): акцентная «мягкая» кнопка в духе iOS —
  /// заливка цветом темы с малой альфой и цветной глиф/подпись, вместо
  /// нейтрально-серой плашки, которая читалась как выключенная.
  Widget _quickAddButton({required IconData icon, required String label, required VoidCallback onTap}) {
    final primary = Theme.of(context).colorScheme.primary;
    return Tappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(AppRadii.button),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(CupertinoIcons.plus, size: 12, color: primary),
          const SizedBox(width: 5),
          Icon(icon, size: 15, color: primary),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: primary)),
        ]),
      ),
    );
  }

  Widget _tabItem(String label) {
    return Tab(
      height: 32,
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, softWrap: false)),
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
            Text(name, style: TextStyle(fontSize: 13, color: adaptiveText3(context)), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.chip),
              child: LinearProgressIndicator(value: progress > 0 ? progress : null, color: Theme.of(context).colorScheme.primary, backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12), minHeight: 5),
            ),
            const SizedBox(height: 6),
            Text(progress > 0 ? '${(progress * 100).toInt()}%' : l.t('downloading'), style: TextStyle(fontSize: 13, color: adaptiveText3(context))),
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
      // Кэш-ключ уходит в имя ПАПКИ, а не файла: иначе он торчит перед названием
      // в системном вьюере/шаринге при открытии.
      final cacheDir = Directory('${dir.path}/dl_${fileCacheKey(cleanUrl)}');
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
      final filePath = '${cacheDir.path}/$safeFileName';
      final file = File(filePath);

      if (!await file.exists()) {
        if (!mounted || cancelled) return;
        final api = context.read<ApiService>();
        // clientForUrl, а не api.dio: файлы лежат в R2, и на чужой хост
        // Authorization отправлять нельзя — иначе access-токен утекает в
        // логи CDN.
        await api.clientForUrl(cleanUrl).download(
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

    final headerSig = '$displayTitle|$displayDesc|${coverImg?.toString() ?? ''}|'
        '${auth.isTeacher}|$isArchivedForUser|${l.t('archived_badge')}';
    if (headerSig != _headerSig || _headerCache == null) {
      _headerSig = headerSig;
      _headerCache = ClassCoverSliver(
        title: displayTitle,
        desc: displayDesc,
        coverImg: coverImg,
        coverIcon: (meta['cover_icon'] ?? clsData['cover_icon']) as String?,
        isTeacher: auth.isTeacher,
        isArchived: isArchivedForUser,
        archivedLabel: l.t('archived_badge'),
        onBack: () => Navigator.pop(context),
        onEdit: _editClass,
        onSettings: _classSettings,
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
              // Вместо падающей тени — волосяная линия по границе с контентом
              // (scroll edge в iOS): тень под панелью выглядела как отдельный
              // «слой Material», наезжающий на список.
              border: Border(bottom: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.07),
                width: 1 / MediaQuery.of(context).devicePixelRatio,
              )),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.all(3),
                  // Капсула, как нативный CupertinoSlidingSegmentedControl.
                  decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(100)),
                  child: TabBar(
                    controller: _tabCtrl,
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicatorAnimation: TabIndicatorAnimation.elastic,
                    indicator: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.08), blurRadius: 3, offset: const Offset(0, 1))],
                    ),
                    splashFactory: NoSplash.splashFactory,
                    overlayColor: WidgetStateProperty.all(Colors.transparent),
                    labelColor: adaptiveText1(context),
                    unselectedLabelColor: adaptiveText3(context),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                    labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                    unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: -0.2),
                    tabs: [
                      _tabItem(l.t('lectures')),
                      _tabItem(l.t('assignments')),
                      _tabItem(l.t('ai_chat')),
                    ],
                  ),
                ),
              ),
              if (auth.isTeacher) AnimatedBuilder(animation: _tabCtrl, builder: (ctx, _) {
                if (_tabCtrl.index == 2) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Row(children: [
                    Expanded(child: _quickAddButton(
                      icon: CupertinoIcons.doc_text,
                      label: l.t('assignment'),
                      onTap: () => _createAssignment(),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _quickAddButton(
                      icon: CupertinoIcons.book,
                      label: l.t('lecture'),
                      onTap: () => _showAddMenu(),
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
                  posts: _lectures, isTeacher: auth.isTeacher,
                  onShowPost: _showPost, onEditPost: _editPost,
                  onDeletePost: (id) async { try { await context.read<ApiService>().deletePost(id); _load(); } catch (_) {} },
                  onRefresh: _load,
                ),
                ClassAssignmentsTab(
                  assignments: _assignments, mySubs: _mySubs, rating: _rating,
                  isTeacher: auth.isTeacher, classId: widget.classId, isLoading: _loadingAsg,
                  viewOnly: viewOnly, cohortId: auth.isTeacher ? _selectedCohortId : null,
                  onRefresh: _loadAssignments, onEditAssignment: _editAssignment,
                  onOpenFile: (url, name) => _openFileViewer(context, url, name),
                ),
                _aiTab(viewOnly),
              ]),
          ),
        ]),
      ),
      floatingActionButton: null,
    );
  }

  void _editPost(dynamic p) async {
    final changed = await guardedPush<bool>(context, MaterialPageRoute(
      builder: (_) => LectureEditorScreen(classId: widget.classId, post: Map<String, dynamic>.from(p as Map)),
    ));
    if (changed == true) _load();
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

  Widget _cohortSelector(L10n l, {VoidCallback? onChangedExtra}) {
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
          borderRadius: BorderRadius.circular(AppRadii.tile),
          border: isViewingPast
              ? Border.all(color: primary.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(children: [
          Icon(CupertinoIcons.calendar, size: 15,
              color: isViewingPast ? primary : C.text4),
          const SizedBox(width: 8),
          Text('${l.t('select_cohort')}:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: isViewingPast ? primary : adaptiveText3(context))),
          const SizedBox(width: 4),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                isExpanded: true,
                isDense: true,
                value: _selectedCohortId ?? activeId ?? (_cohorts.first['id'] as num).toInt(),
                icon: Icon(CupertinoIcons.chevron_down, size: 14,
                    color: isViewingPast ? primary : C.text4),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: adaptiveText1(context)),
                items: [
                  for (final c in _cohorts)
                    DropdownMenuItem<int?>(
                      value: (c['id'] as num).toInt(),
                      child: Text(labelFor(c), overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  hapticSelection();
                  setState(() => _selectedCohortId = (v == activeId) ? null : v);
                  onChangedExtra?.call();
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
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                      color: adaptiveText1(context).withValues(alpha: 0.6))),
            ],
          ),
        ),
      );
    }
    return ClassAiTab(
      classId: widget.classId, className: _title, isActive: _aiTabActive,
      isTeacher: context.read<AuthProvider>().isTeacher,
    );
  }

  void _showPost(dynamic p, int num) {
    String content = '';
    try { final b = jsonDecode(p['body']); content = b['content'] ?? b['description'] ?? ''; }
    catch (_) { content = p['body'] ?? ''; }
    final files = _extractFiles(p);
    final cleanText = cleanContent(content);

    guardedPush(context, MaterialPageRoute(builder: (_) => LectureDetailScreen(
      title: cleanPostTitle(p['title'] ?? ''),
      dateLabel: fmtDate(p['created_at'] ?? ''),
      content: cleanText,
      files: files,
      onOpenFile: _openFileViewer,
    )));
  }

  void _showAddMenu() async {
    final changed = await guardedPush<bool>(context, MaterialPageRoute(
      builder: (_) => LectureEditorScreen(classId: widget.classId),
    ));
    if (changed == true) _load();
  }

  void _createAssignment() async {
    final changed = await guardedPush<bool>(context, MaterialPageRoute(
      builder: (_) => AssignmentEditorScreen(classId: widget.classId),
    ));
    if (changed == true) _loadAssignments();
  }

  Widget _fieldLabel2(String s) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(s, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.text3, letterSpacing: 1)));

  void _editAssignment(dynamic a) async {
    final changed = await guardedPush<bool>(context, MaterialPageRoute(
      builder: (_) => AssignmentEditorScreen(
        classId: widget.classId,
        assignment: Map<String, dynamic>.from(a as Map),
        onManageVariants: _showVariantsSheet,
      ),
    ));
    if (changed == true) _loadAssignments();
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
              decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(AppRadii.chip))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
              Expanded(child: Text(l.t('assignment_variants'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
              IconButton(icon: const Icon(CupertinoIcons.xmark), tooltip: 'Закрыть', onPressed: () => Navigator.pop(ctx)),
            ])),
            Expanded(child: variants == null
                ? Center(child: CupertinoActivityIndicator(radius: 13, color: Theme.of(context).colorScheme.primary))
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
                        child: Center(child: Text(l.t('assignment_variants_empty'), style: TextStyle(color: adaptiveText3(context)))))
                    else
                      ...variants!.map((v) {
                        final vid = (v['id'] as num?)?.toInt();
                        return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.tile)),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text((v['title'] ?? '').toString(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                              if ((v['content'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
                                child: Text((v['content'] ?? '').toString(), style: TextStyle(fontSize: 13, color: adaptiveText3(context)), maxLines: 3, overflow: TextOverflow.ellipsis)),
                            ])),
                            Tappable(
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
                              label: 'Удалить вариант',
                              child: const Padding(padding: EdgeInsets.all(4), child: Icon(CupertinoIcons.trash, size: 16, color: C.red)),
                            ),
                          ]));
                      }),
                  ])),
          ]));
      }),
    ).then((_) {
      Future.delayed(const Duration(milliseconds: 400), () {
        variantTitleC.dispose(); variantContentC.dispose();
      });
    });
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
    // Обложка больше не загружается: преподаватель выбирает цвет и предметную
    // иконку, а картинку рисует бэкенд (POST /classes/{id}/cover/generate).
    // У предмета, созданного до перехода на новую систему, цвета и иконки нет
    // — подставляем значения по умолчанию, а его собственная картинка остаётся
    // на месте, пока преподаватель сам не нажмёт «Сгенерировать».
    String coverImage = (meta['cover_image'] as String?) ?? '';
    String coverColor = (meta['cover_color'] as String?) ?? kFallbackCoverOptions.defaultColor;
    String coverIcon = (meta['cover_icon'] as String?) ?? kFallbackCoverOptions.defaultIcon;
    String? coverSource = meta['cover_source'] as String?;
    bool generatingCover = false;
    String? coverError;
    bool saving = false;

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(expand: false, initialChildSize: 0.85, maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.all(24), children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadii.tile)),
              child: Icon(CupertinoIcons.pencil, color: Theme.of(context).colorScheme.primary, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Text(l.t('edit_class'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
            IconButton(icon: const Icon(CupertinoIcons.xmark), tooltip: 'Закрыть', onPressed: () => Navigator.pop(ctx)),
          ]),
          const SizedBox(height: 24),
          CoverAppearance(
            color: coverColor,
            icon: coverIcon,
            coverUrl: coverImage.isEmpty ? null : coverImage,
            coverSource: coverSource,
            classId: widget.classId,
            generating: generatingCover,
            error: coverError,
            onColorChanged: (v) => setS(() => coverColor = v),
            onIconChanged: (v) => setS(() => coverIcon = v),
            onGenerate: () async {
              if (generatingCover) return;   // защита от двойного нажатия
              setS(() { generatingCover = true; coverError = null; });
              try {
                final res = await context.read<ApiService>().generateClassCover(
                  widget.classId, color: coverColor, icon: coverIcon);
                if (!ctx.mounted) return;
                // Обложку на сервере уже заменили — сбрасываем кэш картинки,
                // иначе на экране класса осталась бы прежняя из памяти/диска.
                _evictCoverCache();
                setS(() {
                  coverImage = (res['cover_image'] as String?) ?? coverImage;
                  coverSource = res['cover_source'] as String?;
                });
                if (mounted) _applyClassUpdate({..._meta, ...res});
              } catch (e) {
                if (!ctx.mounted) return;
                final detail = (e is DioException && e.response?.data is Map)
                    ? e.response?.data['detail'] : null;
                setS(() => coverError = detail == 'too_many_cover_generations'
                    ? l.t('cover_rate_limited')
                    : l.t('cover_generate_failed'));
              } finally {
                if (ctx.mounted) setS(() => generatingCover = false);
              }
            },
          ),
          const SizedBox(height: 20),
          _fieldLabel2('${l.t('class_name')} *'),
          TextField(controller: tc, decoration: InputDecoration(hintText: l.t('class_name_simple_hint'))),
          const SizedBox(height: 16),
          _fieldLabel2(l.t('class_desc')),
          TextField(controller: dc, decoration: InputDecoration(hintText: l.t('class_desc_simple_hint')), maxLines: 3),
          const SizedBox(height: 16),
          _fieldLabel2(l.t('teacher_name_label')),
          TextField(controller: tn, decoration: InputDecoration(hintText: l.t('teacher_display_hint'))),
          const SizedBox(height: 28),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: saving ? null : () => Navigator.pop(ctx), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)), child: Text(l.t('cancel')))),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: (saving || generatingCover) ? null : () async {
                setS(() => saving = true);
                try {
                  final api = context.read<ApiService>();
                  // Картинку меняет только генерация; здесь передаём лишь цвет
                  // с иконкой — если их поменяли без генерации, бэкенд
                  // перерисует обложку локальным фолбэком, мгновенно и бесплатно.
                  final appearanceChanged = coverColor != meta['cover_color']
                      || coverIcon != meta['cover_icon'];
                  final updated = await api.updateClass(widget.classId,
                      name: tc.text.trim(),
                      description: dc.text.trim(),
                      teacher: tn.text.trim(),
                      coverColor: coverColor,
                      coverIcon: coverIcon);
                  if (!mounted || !ctx.mounted) return;
                  if (appearanceChanged) _evictCoverCache();
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
        ])))).then((_) {
      Future.delayed(const Duration(milliseconds: 400), () {
        tc.dispose(); dc.dispose(); tn.dispose();
      });
    });
  }

  void _classSettings() {
    final l = context.read<L10n>();
    final inviteCode = (_meta['invite_code'] as String?) ?? '';
    bool rotationYearly = (_meta['rotation_mode'] == 'yearly');
    bool savingRotation = false;
    bool codeCopied = false;

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(expand: false, initialChildSize: 0.6, maxChildSize: 0.9,
        builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.all(24), children: [
          Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadii.tile)),
              child: Icon(CupertinoIcons.gear_alt_fill, color: Theme.of(context).colorScheme.primary, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Text(l.t('class_settings'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
            IconButton(icon: const Icon(CupertinoIcons.xmark), tooltip: 'Закрыть', onPressed: () => Navigator.pop(ctx)),
          ]),
          const SizedBox(height: 20),
          if (inviteCode.isNotEmpty) ...[
            _fieldLabel2(l.t('class_code')),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Tappable(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: inviteCode));
                  showToast(context, '${l.t('code_copied')}: $inviteCode');
                  setS(() => codeCopied = true);
                  Future.delayed(const Duration(seconds: 2), () { if (ctx.mounted) setS(() => codeCopied = false); });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: adaptivePrimaryLt(context), borderRadius: BorderRadius.circular(AppRadii.chip)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(codeCopied ? CupertinoIcons.checkmark_alt : CupertinoIcons.doc_on_doc, size: 14, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(codeCopied ? l.t('code_copied') : inviteCode, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary, letterSpacing: codeCopied ? 0 : 2)),
                  ]),
                ),
              ),
              Tappable(
                onTap: () async { Navigator.pop(ctx); await _regenerateCode(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.chip), border: Border.all(color: adaptiveBorder(context))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(CupertinoIcons.refresh, size: 14, color: adaptiveText3(context)),
                    const SizedBox(width: 6),
                    Text(l.t('regenerate_code'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: adaptiveText3(context))),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 20),
          ],
          if (_canManageCohorts && _cohorts.length > 1) ...[
            _cohortSelector(l, onChangedExtra: () => setS(() {})),
            const SizedBox(height: 16),
          ],
          if (_canManageCohorts) ...[
            Container(
              decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.tile)),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                value: rotationYearly,
                onChanged: savingRotation ? null : (v) async {
                  setS(() { rotationYearly = v; savingRotation = true; });
                  try {
                    await context.read<ApiService>().setRotationMode(widget.classId, v ? 'yearly' : 'manual');
                    setState(() => _meta = {..._meta, 'rotation_mode': v ? 'yearly' : 'manual'});
                  } catch (_) {
                    if (ctx.mounted) setS(() => rotationYearly = !v);
                  }
                  if (ctx.mounted) setS(() => savingRotation = false);
                },
                title: Text(l.t('yearly_rotation'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(l.t('yearly_rotation_sub'), style: TextStyle(fontSize: 13, color: adaptiveText3(context))),
                ),
              ),
            ),
            if (rotationYearly) ...[
              const SizedBox(height: 12),
              Tappable(
                onTap: () async {
                  Navigator.pop(ctx);
                  final changed = await guardedPush<bool>(context,
                      MaterialPageRoute(builder: (_) => const RolloverScreen()));
                  if (changed == true && mounted) _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)),
                  ),
                  child: Row(children: [
                    Icon(CupertinoIcons.calendar_badge_plus, size: 19, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l.t('new_academic_year'),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary))),
                    Icon(CupertinoIcons.chevron_right, size: 15, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)),
                  ]),
                ),
              ),
            ],
          ],
          const SizedBox(height: 16),
        ])))).then((_) {});
  }

  @override void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }
}
