import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/network_cover_image.dart';
import '../../widgets/subject_cover.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../providers/classes_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_cache.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/tappable.dart';
import '../../widgets/toast.dart';
import '../notifications/notifications_screen.dart';
import '../calendar/calendar_screen.dart';
import '../../utils/haptics.dart';
import '../../utils/nav_guard.dart';
import '../classes/join_class_dialog.dart';
import '../classes/create_class_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  Set<int> _pinnedIds = {};
  Map<int, int> _classOrder = {};
  bool _showDragHint = false;
  late AnimationController _headerCtrl;
  late Animation<double> _headerAnim;
  late final ClassesProvider _classesProvider = context.read<ClassesProvider>();

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _headerAnim = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOutCubic);
    _headerCtrl.forward();
    final provider = _classesProvider;
    provider.addListener(_onProviderError);
    // После первого кадра: load() синхронно зовёт notifyListeners(), а во
    // время начального build это «setState() called during build».
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      provider.loadJoined();
      provider.load();
      provider.loadNotifBadge();
    });
    _loadPersistedState();
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _classesProvider.removeListener(_onProviderError);
    super.dispose();
  }

  Future<void> _loadPersistedState() async {
    final uid = context.read<AuthProvider>().userId ?? 0;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final pinnedList = prefs.getStringList('pinned_classes_$uid') ?? [];
    final orderJson = prefs.getString('class_order_$uid');
    final shown = prefs.getBool('shown_drag_hint_$uid') ?? false;
    Map<int, int> order = {};
    if (orderJson != null) {
      try {
        final map = jsonDecode(orderJson) as Map<String, dynamic>;
        order = map.map((k, v) => MapEntry(int.parse(k), v as int));
      } catch (_) {}
    }
    setState(() {
      _pinnedIds = pinnedList.map(int.parse).toSet();
      _classOrder = order;
      _showDragHint = _classOrder.isEmpty && !shown;
    });
  }

  Future<void> _savePinned() async {
    final uid = context.read<AuthProvider>().userId ?? 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pinned_classes_$uid', _pinnedIds.map((e) => e.toString()).toList());
  }

  Future<void> _saveOrder() async {
    final uid = context.read<AuthProvider>().userId ?? 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('class_order_$uid',
      jsonEncode(_classOrder.map((k, v) => MapEntry(k.toString(), v))));
  }

  Future<void> _dismissDragHint() async {
    final uid = context.read<AuthProvider>().userId ?? 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shown_drag_hint_$uid', true);
    if (!mounted) return;
    setState(() => _showDragHint = false);
  }

  List<Map<String, dynamic>> get _sortedClasses {
    final provider = context.read<ClassesProvider>();
    final all = provider.activeClasses;
    final pinned = all.where((c) => _pinnedIds.contains(c['id'] as int)).toList();
    final regular = all.where((c) => !_pinnedIds.contains(c['id'] as int)).toList();
    pinned.sort((a, b) {
      final oa = _classOrder[a['id'] as int] ?? 9999;
      final ob = _classOrder[b['id'] as int] ?? 9999;
      return oa.compareTo(ob);
    });
    regular.sort((a, b) {
      final oa = _classOrder[a['id'] as int] ?? 9999;
      final ob = _classOrder[b['id'] as int] ?? 9999;
      return oa.compareTo(ob);
    });
    return [...pinned, ...regular];
  }

  void _onReorderItem(int oldIndex, int newIndex) {
    final classes = _sortedClasses;
    final pinnedCount = _pinnedIds.length;
    final isOldPinned = oldIndex < pinnedCount;
    final isNewPinned = newIndex < pinnedCount;
    if (isOldPinned != isNewPinned) {
      hapticHeavy();
      return;
    }
    hapticLight();
    final list = classes.toList();
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    setState(() {
      for (int i = 0; i < list.length; i++) {
        _classOrder[list[i]['id'] as int] = i;
      }
    });
    _saveOrder();
  }

  void _onProviderError() {
    final err = context.read<ClassesProvider>().errorMessage;
    if (err != null && mounted) {
      showToast(context, context.read<L10n>().t(err), error: true);
      context.read<ClassesProvider>().clearError();
    }
  }

  static const _grads = [
    [Color(0xFF006475), Color(0xFF009AAF)],
    [Color(0xFF0C4A6E), Color(0xFF0369A1)],
    [Color(0xFF134E4A), Color(0xFF0D9488)],
    [Color(0xFF312E81), Color(0xFF4338CA)],
    [Color(0xFF1E3A5F), Color(0xFF2563EB)],
  ];

  @override
  Widget build(BuildContext context) {
    final auth    = context.watch<AuthProvider>();
    final l       = context.watch<L10n>();
    final provider = context.watch<ClassesProvider>();
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      // bottom: false — список едет edge-to-edge под плавающий навбар (как в
      // Telegram/нативных iOS-приложениях), а не упирается в safe-area снизу
      // отдельным сплошным "коробом". Реальный клиренс над навбаром уже даёт
      // bottomBarClearance() (см. концевой SliverToBoxAdapter ниже и
      // SliverPadding у пустого/лоадинг состояний) — он и так учитывает
      // safe-area, так что убирать его отсюда безопасно.
      body: SafeArea(bottom: false, child: CustomScrollView(slivers: [
          CupertinoSliverRefreshControl(
            onRefresh: () {
              final p = context.read<ClassesProvider>();
              return Future.wait([
                p.load(),
                p.loadJoined(),
                p.loadNotifBadge(),
              ]);
            },
          ),

          SliverToBoxAdapter(child: AnimatedBuilder(
            animation: _headerAnim,
            builder: (_, child) => Opacity(
              opacity: _headerAnim.value,
              child: Transform.translate(offset: Offset(0, -12 * (1 - _headerAnim.value)), child: child),
            ),
            child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            child: Row(children: [
              Expanded(child: Text(l.t('classes'), style: TextStyle(
                fontSize: 34, fontWeight: FontWeight.w700,
                color: adaptiveText1(context), letterSpacing: -0.4, height: 1.1,
              ))),
              const SizedBox(width: 8),
              if (!auth.isTeacher) ...[
                _HeaderBtn(icon: CupertinoIcons.calendar, onTap: _openCalendar, isDark: isDark, label: 'Открыть календарь'),
                const SizedBox(width: 8),
              ],
              if (auth.isTeacher) ...[
                Tappable(onTap: _showCreateClass,
                  label: 'Создать класс',
                  child: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(AppRadii.tile),
                      boxShadow: primaryGlow(primary, opacity: 0.30),
                    ),
                    child: const Icon(CupertinoIcons.add, color: Colors.white, size: 20),
                  )),
              ] else ...[
                Tappable(
                  // Бейдж обновляется изнутри NotificationsScreen (сразу при
                  // прочтении/дисмиссе), поэтому повторный fetch после
                  // возврата не нужен — наоборот, он может обогнать серверную
                  // запись о прочтении и откатить счётчик обратно на старое
                  // значение.
                  onTap: () => guardedPush(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                  label: 'Открыть уведомления',
                  child: Stack(clipBehavior: Clip.none, children: [
                    _HeaderBtn(icon: CupertinoIcons.bell, onTap: null, isDark: isDark),
                    Positioned(top: -4, right: -4, child: ValueListenableBuilder<int>(
                      valueListenable: context.read<ClassesProvider>().notifBadge,
                      builder: (context, count, _) => count > 0
                          ? Container(
                              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: C.red,
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                              ),
                              child: Text(
                                count > 99 ? '99+' : '$count',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, height: 1.15),
                              ),
                            )
                          : const SizedBox.shrink(),
                    )),
                  ]),
                ),
                const SizedBox(width: 8),
                Tappable(onTap: _showJoinDialog,
                  label: 'Вступить по коду',
                  child: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(AppRadii.tile),
                      boxShadow: primaryGlow(primary, opacity: 0.30),
                    ),
                    child: const Icon(CupertinoIcons.lock, color: Colors.white, size: 18))),
              ],
            ]),
          ))),

          if (provider.loading && provider.classes.isEmpty)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, bottomBarClearance(context)),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) => TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 250 + i * 80),
                  curve: Curves.easeOut,
                  builder: (_, t, child) => Opacity(opacity: t, child: child),
                  child: const SkeletonClassCard(),
                ),
                childCount: 3,
              )),
            )
          else if (provider.classes.isEmpty)
            SliverFillRemaining(child: _EmptyState(isTeacher: auth.isTeacher, onCreate: _showCreateClass, onJoin: _showJoinDialog))
          else ...[
            if (_showDragHint)
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: adaptivePrimaryLt(context),
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                  ),
                  child: Row(children: [
                    Icon(CupertinoIcons.line_horizontal_3, color: primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l.t('drag_hint'),
                      style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w500))),
                    Tappable(
                      onTap: _dismissDragHint,
                      label: 'Скрыть подсказку',
                      child: Icon(CupertinoIcons.xmark, color: primary, size: 18),
                    ),
                  ]),
                ),
              )),
            Builder(builder: (context) {
              final sortedClasses = _sortedClasses;
              return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              sliver: SliverReorderableList(
                onReorderItem: _onReorderItem,
                proxyDecorator: (child, _, animation) => Transform.scale(
                  scale: 1.03,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      boxShadow: [BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 40, offset: Offset(0, 12),
                      )],
                    ),
                    child: child,
                  ),
                ),
                itemCount: sortedClasses.length,
                itemBuilder: (ctx, i) {
                  final cls = sortedClasses[i];
                  final id  = cls['id'] as int;
                  final card = _ClassCard(
                    key: ValueKey(id),
                    cls: cls,
                    index: i,
                    colors: _grads[id % _grads.length],
                    isPinned: _pinnedIds.contains(id),
                    isTeacher: auth.isTeacher,
                    openLabel: l.t('open'),
                    codeCopiedLabel: l.t('code_copied'),
                    deleteLabel: l.t('delete_class'),
                    noLabel: l.t('no'),
                    deleteConfirmLabel: l.t('delete'),
                    leaveLabel: l.t('leave_class'),
                    leaveSub: l.t('leave_class_sub'),
                    leaveBtnLabel: l.t('leave_btn'),
                    onTap: () { hapticLight(); guardedPushNamed(context, '/class', arguments: id); },
                    onLongPress: () { hapticHeavy(); _showContextMenu(cls); },
                    onDelete: () async {
                      final prov = context.read<ClassesProvider>();
                      final ok = await prov.deleteClass(id);
                      if (!context.mounted) return;
                      showToast(context, ok
                          ? context.read<L10n>().t('class_deleted')
                          : context.read<L10n>().t(prov.errorMessage ?? 'error'), error: !ok);
                    },
                    onLeave: () async {
                      await context.read<ClassesProvider>().leaveClass(id);
                      if (context.mounted) showToast(context, context.read<L10n>().t('left_class'));
                    },
                    onCopyCode: () {
                      final code = (cls['invite_code'] ?? '').toString();
                      if (code.isEmpty) return;
                      Clipboard.setData(ClipboardData(text: code));
                      showToast(context, '${l.t('code_copied')}: $code');
                    },
                  );
                  return card;
                },
                ),
              );
            }),
          ],

          if (provider.archivedClasses.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _ArchiveEntry(
                  count: provider.archivedClasses.length,
                  onTap: () {
                    hapticLight();
                    guardedPushNamed(context, '/archive');
                  },
                ),
              ),
            ),

          // Карточка "Добавить предмет" после списка классов — убрана по
          // просьбе: у студента и так есть кнопка вступления по коду в шапке
          // экрана (_showJoinDialog там же), дублировать её отдельной
          // карточкой снизу не нужно.
          if (!provider.loading)
            SliverToBoxAdapter(child: SizedBox(height: bottomBarClearance(context))),
        ]),
      ),
    );
  }

  void _showContextMenu(Map<String, dynamic> cls) {
    final auth = context.read<AuthProvider>();
    final l = context.read<L10n>();
    final id = cls['id'] as int;
    final title = cls['title'] ?? '';
    final code = (cls['invite_code'] ?? '').toString();
    final isPinned = _pinnedIds.contains(id);
    final colors = _grads[id % _grads.length];
    final coverImg = cardCoverUrl(cls);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const SizedBox(),
      transitionBuilder: (ctx, anim, __, ___) {
        return Stack(children: [
          GestureDetector(onTap: () => Navigator.pop(ctx)),
          Center(child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
            child: FadeTransition(
              opacity: anim,
              child: _ClassContextMenu(
                cls: cls,
                isTeacher: auth.isTeacher,
                isPinned: isPinned,
                colors: colors,
                coverImg: coverImg,
                title: title,
                onCopyCode: () {
                  Navigator.pop(ctx);
                  if (code.isEmpty) return;
                  Clipboard.setData(ClipboardData(text: code));
                  showToast(context, '${l.t('code_copied')}: $code');
                },
                onShare: () {
                  Navigator.pop(ctx);
                  if (code.isEmpty) return;
                  launchUrl(Uri.parse('chatra://class/$code'));
                },
                onTogglePin: () {
                  Navigator.pop(ctx);
                  setState(() {
                    if (isPinned) { _pinnedIds.remove(id); } else { _pinnedIds.add(id); }
                  });
                  _savePinned();
                },
                onLeave: () async {
                  Navigator.pop(ctx);
                  final ok = await showConfirmDialog(context,
                    title: l.t('leave_class'),
                    message: l.t('leave_class_sub'),
                    icon: CupertinoIcons.arrow_right_square,
                    danger: true,
                    confirmText: l.t('leave_btn'),
                    cancelText: l.t('no'));
                  if (!mounted) return;
                  if (ok == true) {
                    await context.read<ClassesProvider>().leaveClass(id);
                    if (!mounted) return;
                    showToast(context, l.t('left_class'));
                  }
                },
                onDelete: () async {
                  Navigator.pop(ctx);
                  final nameCtrl = TextEditingController();
                  final ok = await showAppDialog<bool>(context, builder: (c) => StatefulBuilder(builder: (c, setS) {
                    final match = nameCtrl.text.trim() == title;
                    return AppDialogCard(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const AppDialogIcon(icon: CupertinoIcons.trash, color: C.red),
                      const SizedBox(height: 14),
                      Text(l.t('delete_class'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: adaptiveText1(c), letterSpacing: -0.3)),
                      const SizedBox(height: 6),
                      Text(l.t('confirm_delete_hint'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: adaptiveText3(c), height: 1.45)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(hintText: title),
                        onChanged: (_) => setS(() {}),
                      ),
                      const SizedBox(height: 16),
                      AppDialogActions(
                        cancelText: l.t('cancel'),
                        confirmText: l.t('delete'),
                        danger: true,
                        onCancel: () => Navigator.pop(c, false),
                        onConfirm: match ? () => Navigator.pop(c, true) : null,
                      ),
                    ]));
                  }));
                  if (!mounted) return;
                  if (ok == true) {
                    final prov = context.read<ClassesProvider>();
                    final done = await prov.deleteClass(id);
                    if (!mounted) return;
                    showToast(context, done ? l.t('class_deleted') : l.t(prov.errorMessage ?? 'error'), error: !done);
                  }
                },
              ),
            ),
          )),
        ]);
      },
    );
  }

  void _openCalendar() {
    guardedPush(context, MaterialPageRoute(builder: (_) => const CalendarScreen()));
  }

  void _showJoinDialog() {
    showJoinClassDialog(context);
  }

  Future<void> _showCreateClass() async {
    final provider = context.read<ClassesProvider>();
    final created = await guardedPush<Map<String, dynamic>>(
      context, MaterialPageRoute(builder: (_) => const CreateClassScreen()));
    if (created != null && mounted) {
      provider.addCreatedClass(created);
      provider.load();
    }
  }
}

class _ClassContextMenu extends StatelessWidget {
  final Map<String, dynamic> cls;
  final bool isTeacher;
  final bool isPinned;
  final List<Color> colors;
  final dynamic coverImg;
  final String title;
  final VoidCallback onCopyCode;
  final VoidCallback onShare;
  final VoidCallback onTogglePin;
  final VoidCallback onLeave;
  final VoidCallback onDelete;

  const _ClassContextMenu({
    required this.cls,
    required this.isTeacher,
    required this.isPinned,
    required this.colors,
    required this.coverImg,
    required this.title,
    required this.onCopyCode,
    required this.onShare,
    required this.onTogglePin,
    required this.onLeave,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final bg2 = adaptiveSurface2(context);
    final primary = Theme.of(context).colorScheme.primary;
    final code = (cls['invite_code'] as String?) ?? '';
    final teacherName = cls['teacher_name'] as String? ?? '';
    // Кэш-растр должен покрывать физические пиксели карточки (288 логических
    // × DPR), иначе на retina-экранах картинка декодируется мельче виджета и
    // растягивается — отсюда размытость.
    final coverCacheWidth = (288 * MediaQuery.of(context).devicePixelRatio).round();

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 288,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          boxShadow: cardShadow(isDark),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Column(mainAxisSize: MainAxisSize.min, children: [

            SizedBox(height: 110, width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                coverImg != null && coverImg.toString().startsWith('data:')
                    ? Builder(builder: (_) { final bytes = decodeBase64Image(coverImg.toString()); return bytes != null ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: coverCacheWidth) : Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors))); })
                    : coverImg != null
                        ? NetworkCoverImage(url: context.read<ApiService>().fixUrl(coverImg.toString()), memCacheWidth: coverCacheWidth, errorBuilder: (_) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors))))
                        : Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight))),
                SubjectIconOverlay(icon: cls['cover_icon'] as String?, size: 34),
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                )))),
                Positioned(bottom: 10, left: 12,
                  child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (teacherName.isNotEmpty)
                  Positioned(bottom: 10, right: 12,
                    child: Text(teacherName, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),

            if (code.isNotEmpty) Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                    border: Border.all(color: primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(CupertinoIcons.tag, size: 12, color: primary),
                    const SizedBox(width: 4),
                    Text(code, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary, letterSpacing: 2)),
                  ]),
                ),
                const Spacer(),
                _SmallAction(icon: CupertinoIcons.doc_on_doc, bg: primary.withValues(alpha: 0.1), iconColor: primary, onTap: onCopyCode, label: 'Скопировать код приглашения'),
              ]),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Column(children: [
                _ActionRow(
                  icon: isPinned ? CupertinoIcons.pin : CupertinoIcons.pin_fill,
                  iconBg: primary.withValues(alpha: 0.12),
                  iconColor: primary,
                  label: isPinned ? l.t('unpin_class') : l.t('pin_class'),
                  bg: bg2,
                  onTap: onTogglePin,
                ),
              ]),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: _ActionRow(
                icon: isTeacher ? CupertinoIcons.trash : CupertinoIcons.arrow_right_square,
                iconBg: C.red.withValues(alpha: 0.12),
                iconColor: C.red,
                label: isTeacher ? l.t('delete_class') : l.t('leave_class'),
                bg: C.red.withValues(alpha: isDark ? 0.08 : 0.05),
                textColor: C.red,
                onTap: isTeacher ? onDelete : onLeave,
              ),
            ),

          ]),
        ),
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color iconColor;
  final VoidCallback onTap;
  final String? label;
  const _SmallAction({required this.icon, required this.bg, required this.iconColor, required this.onTap, this.label});

  @override
  Widget build(BuildContext context) => Tappable(
    onTap: onTap,
    label: label,
    child: Container(
      width: 34, height: 34,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadii.chip)),
      child: Icon(icon, size: 16, color: iconColor),
    ),
  );
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final Color bg;
  final Color? textColor;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.bg,
    required this.onTap,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = textColor ?? adaptiveText1(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        child: Ink(
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadii.tile)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(AppRadii.chip)),
                child: Icon(icon, size: 17, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: labelColor))),
              Icon(CupertinoIcons.chevron_right, size: 16, color: labelColor.withValues(alpha: 0.35)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ArchiveEntry extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _ArchiveEntry({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            boxShadow: cardShadow(isDark),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: adaptiveSurface2(context),
                borderRadius: BorderRadius.circular(AppRadii.tile),
              ),
              child: Icon(CupertinoIcons.archivebox, size: 21,
                  color: adaptiveText1(context).withValues(alpha: 0.65)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.t('archive'),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                        color: adaptiveText1(context), letterSpacing: -0.3)),
                const SizedBox(height: 1),
                Text(l.t('archive_entry_sub'),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13,
                        color: adaptiveText1(context).withValues(alpha: 0.5))),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: adaptiveText1(context).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text('$count',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: adaptiveText1(context).withValues(alpha: 0.6))),
            ),
            const SizedBox(width: 6),
            Icon(CupertinoIcons.chevron_right, size: 17,
                color: adaptiveText1(context).withValues(alpha: 0.4)),
          ]),
        ),
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final Map<String, dynamic> cls;
  final int index;
  final List<Color> colors;
  final bool isPinned;
  final bool isTeacher;
  final String openLabel;
  final String codeCopiedLabel;
  final String deleteLabel;
  final String noLabel;
  final String deleteConfirmLabel;
  final String leaveLabel;
  final String leaveSub;
  final String leaveBtnLabel;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final Future<void> Function() onDelete;
  final Future<void> Function() onLeave;
  final VoidCallback onCopyCode;

  const _ClassCard({
    super.key,
    required this.cls,
    required this.index,
    required this.colors,
    required this.isPinned,
    required this.isTeacher,
    required this.openLabel,
    required this.codeCopiedLabel,
    required this.deleteLabel,
    required this.noLabel,
    required this.deleteConfirmLabel,
    required this.leaveLabel,
    required this.leaveSub,
    required this.leaveBtnLabel,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    required this.onLeave,
    required this.onCopyCode,
  });

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final surface  = Theme.of(context).colorScheme.surface;
    final coverImg = cardCoverUrl(cls);
    final teacherName = cls['teacher_name'] ?? '';
    // Карточка на всю ширину экрана — берём ширину экрана как верхнюю
    // границу физического размера, чтобы не декодировать мельче виджета
    // на retina-экранах.
    final coverCacheWidth = (MediaQuery.of(context).size.width * MediaQuery.of(context).devicePixelRatio).round();

    return RepaintBoundary(
      child: Tappable(
        onTap: onTap,
        onLongPress: onLongPress,
        scale: 0.98,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            boxShadow: cardShadow(isDark),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: SizedBox(height: 168, width: double.infinity,
                child: Stack(fit: StackFit.expand, children: [
                  Builder(builder: (_) {
                    final gradient = Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)));
                    if (coverImg == null) return gradient;
                    return coverImg.toString().startsWith('data:')
                        ? Builder(builder: (_) {
                            final bytes = decodeBase64Image(coverImg.toString());
                            return bytes != null
                                ? Image.memory(bytes, fit: BoxFit.cover, width: double.infinity, gaplessPlayback: true, cacheWidth: coverCacheWidth)
                                : gradient;
                          })
                        : NetworkCoverImage(
                            url: context.read<ApiService>().fixUrl(coverImg.toString()),
                            memCacheWidth: coverCacheWidth,
                            errorBuilder: (_) => gradient,
                          );
                  }),
                  SubjectIconOverlay(icon: cls['cover_icon'] as String?, size: 44),
                  Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    stops: const [0.5, 1.0],
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
                  )))),
                  if (isTeacher && (cls['invite_code'] as String? ?? '').isNotEmpty)
                    Positioned(top: 10, left: 10, child: Tappable(
                      onTap: onCopyCode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(AppRadii.chip)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(CupertinoIcons.doc_on_doc, size: 11, color: Colors.white60),
                          const SizedBox(width: 4),
                          Text(cls['invite_code'] as String, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 2)),
                        ]),
                      ))),
                  if (isPinned)
                    const Positioned(top: 10, right: 10, child: Icon(CupertinoIcons.pin_fill, color: Colors.white, size: 18)),
                  Positioned(bottom: 8, right: 8,
                    child: ReorderableDragStartListener(
                      index: index,
                      child: SizedBox(width: 44, height: 44,
                        child: Center(child: Icon(CupertinoIcons.line_horizontal_3, size: 20, color: Colors.white.withValues(alpha: 0.5)))),
                    )),
                ]),
              ),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cls['title'] ?? '', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: adaptiveText1(context), height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (teacherName.isNotEmpty) _MetaChip(label: teacherName, icon: CupertinoIcons.person, isDark: isDark),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.chip)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(openLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: adaptiveText1(context))),
                    const SizedBox(width: 4),
                    Icon(CupertinoIcons.arrow_right, size: 14, color: adaptiveText1(context)),
                  ]),
                ),
                const Spacer(),
                if (isTeacher) _ActionBtn(
                  icon: CupertinoIcons.trash, color: C.text4, isDark: isDark,
                  label: 'Удалить класс',
                  onTap: () async {
                    final ok = await showConfirmDialog(context,
                      title: deleteLabel,
                      icon: CupertinoIcons.trash,
                      danger: true,
                      confirmText: deleteConfirmLabel,
                      cancelText: noLabel);
                    if (ok == true) await onDelete();
                  },
                ),
                if (!isTeacher) _ActionBtn(
                  icon: CupertinoIcons.arrow_right_square, color: C.text4, isDark: isDark,
                  label: 'Покинуть класс',
                  onTap: () async {
                    final ok = await showConfirmDialog(context,
                      title: leaveLabel,
                      message: leaveSub,
                      icon: CupertinoIcons.arrow_right_square,
                      danger: true,
                      confirmText: leaveBtnLabel,
                      cancelText: noLabel);
                    if (ok == true) await onLeave();
                  },
                ),
              ]),
            ])),
          ]),
        ),
      ),
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDark;
  final String? label;
  const _HeaderBtn({required this.icon, required this.onTap, required this.isDark, this.label});

  @override
  Widget build(BuildContext context) => Tappable(
    onTap: onTap,
    label: label,
    child: Container(width: 42, height: 42,
      decoration: BoxDecoration(
        color: adaptiveSurface2(context),
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: Border.all(color: adaptiveBorder(context)),
      ),
      child: Icon(icon,
        color: Theme.of(context).brightness == Brightness.dark ? C.darkText2 : C.text3,
        size: 19)),
  );
}

class _MetaChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  const _MetaChip({required this.label, required this.icon, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final c = adaptiveText3(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c)),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;
  final String? label;
  const _ActionBtn({required this.icon, required this.color, required this.isDark, required this.onTap, this.label});

  @override
  Widget build(BuildContext context) => Tappable(
    onTap: onTap,
    label: label,
    child: Container(width: 34, height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Icon(icon, size: 17, color: color)),
  );
}

class _EmptyState extends StatelessWidget {
  final bool isTeacher;
  final VoidCallback onCreate, onJoin;
  const _EmptyState({required this.isTeacher, required this.onCreate, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final l = context.read<L10n>();
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 88, height: 88,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary.withValues(alpha: 0.18), Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)]),
            shape: BoxShape.circle,
          ),
          child: Icon(CupertinoIcons.book, color: Theme.of(context).colorScheme.primary, size: 40)),
        const SizedBox(height: 22),
        Text(l.t('no_classes'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: adaptiveText1(context), letterSpacing: -0.4)),
        const SizedBox(height: 8),
        Text(isTeacher ? l.t('create_first_class') : l.t('enter_teacher_code'),
          style: TextStyle(fontSize: 15, color: adaptiveText3(context)), textAlign: TextAlign.center),
        const SizedBox(height: 28),
        if (isTeacher) ...[
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(CupertinoIcons.add, size: 18),
            label: Text(l.t('create_class')),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
        ] else
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: onJoin,
            icon: const Icon(CupertinoIcons.lock, size: 18),
            label: Text(l.t('enter_code')),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
      ]),
    ));
  }
}
