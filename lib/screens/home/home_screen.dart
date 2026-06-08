import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../providers/classes_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/class_utils.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/toast.dart';
import '../notifications/notifications_screen.dart';
import '../calendar/calendar_screen.dart';
import '../classes/class_detail_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _headerAnim = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOutCubic);
    _headerCtrl.forward();
    final provider = context.read<ClassesProvider>();
    provider.addListener(_onProviderError);
    provider.loadJoined().then((_) => provider.load());
    provider.loadNotifBadge();
    _loadPersistedState();
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    context.read<ClassesProvider>().removeListener(_onProviderError);
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
    final all = provider.classes;
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

  void _onReorder(int oldIndex, int newIndex) {
    final classes = _sortedClasses;
    final pinnedCount = _pinnedIds.length;
    // Prevent mixing pinned/regular zones
    final isOldPinned = oldIndex < pinnedCount;
    final adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final isNewPinned = adjustedNew < pinnedCount;
    if (isOldPinned != isNewPinned) {
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.lightImpact();
    if (newIndex > oldIndex) newIndex -= 1;
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
      showToast(context, err, error: true);
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
    final surface = Theme.of(context).colorScheme.surface;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        color: primary,
        onRefresh: () => context.read<ClassesProvider>().load(),
        child: CustomScrollView(slivers: [

          // ── Header ──────────────────────────────────────────
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
                fontSize: 30, fontWeight: FontWeight.w900,
                color: primary, letterSpacing: -0.8, height: 1.1,
              ))),
              const SizedBox(width: 8),
              _HeaderBtn(icon: Icons.calendar_month_rounded, onTap: _openCalendar, isDark: isDark),
              const SizedBox(width: 8),
              if (auth.isTeacher) ...[
                if (!auth.isAdmin) ...[
                  _HeaderBtn(icon: Icons.vpn_key_rounded, onTap: _showJoinDialog, isDark: isDark),
                  const SizedBox(width: 8),
                ],
                GestureDetector(onTap: _showCreateClass,
                  child: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: primaryGlow(primary, opacity: 0.30),
                    ),
                    child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                  )),
              ] else ...[
                GestureDetector(
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                    if (!mounted) return;
                    context.read<ClassesProvider>().loadNotifBadge();
                  },
                  child: Stack(children: [
                    _HeaderBtn(icon: Icons.notifications_outlined, onTap: null, isDark: isDark),
                    if (provider.unreadNotifCount > 0)
                      Positioned(top: 7, right: 7, child: Container(
                        width: 9, height: 9,
                        decoration: BoxDecoration(
                          color: C.red, shape: BoxShape.circle,
                          border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                        ),
                      )),
                  ]),
                ),
                const SizedBox(width: 8),
                GestureDetector(onTap: _showJoinDialog,
                  child: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: primaryGlow(primary, opacity: 0.30),
                    ),
                    child: const Icon(Icons.vpn_key_rounded, color: Colors.white, size: 18))),
              ],
            ]),
          ))),

          // ── Class cards ──────────────────────────────────────
          if (provider.loading)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
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
            // Drag hint banner
            if (_showDragHint)
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: adaptivePrimaryLt(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Icon(Icons.drag_indicator_rounded, color: primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l.t('drag_hint'),
                      style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w500))),
                    GestureDetector(
                      onTap: _dismissDragHint,
                      child: Icon(Icons.close, color: primary, size: 18),
                    ),
                  ]),
                ),
              )),
            Builder(builder: (context) {
              // Cache once — getter runs filter+sort, don't call per itemBuilder
              final sortedClasses = _sortedClasses;
              return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              sliver: SliverReorderableList(
                onReorder: _onReorder,
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
                    lectureCount: provider.lectureCount(id),
                    isTeacher: auth.isTeacher,
                    openLabel: l.t('open'),
                    codeCopiedLabel: l.t('code_copied'),
                    deleteLabel: l.t('delete_class'),
                    noLabel: l.t('no'),
                    deleteConfirmLabel: l.t('delete'),
                    leaveLabel: l.t('leave_class'),
                    leaveSub: l.t('leave_class_sub'),
                    leaveBtnLabel: l.t('leave_btn'),
                    onTap: () => Navigator.pushNamed(context, '/class', arguments: id),
                    onLongPress: () { HapticFeedback.heavyImpact(); _showContextMenu(cls); },
                    onDelete: () async {
                      await context.read<ClassesProvider>().deleteClass(id);
                      if (mounted) showToast(context, context.read<L10n>().t('class_deleted'));
                    },
                    onLeave: () async {
                      await context.read<ClassesProvider>().leaveClass(id);
                      if (mounted) showToast(context, context.read<L10n>().t('left_class'));
                    },
                    onCopyCode: () {
                      Clipboard.setData(ClipboardData(text: classCode(id)));
                      showToast(context, '${l.t('code_copied')}: ${classCode(id)}');
                    },
                  );
                  return card;
                },
                ),
              );
            }),
          ],

          // "Add subject" card — students only
          if (!auth.isTeacher && !provider.loading && provider.classes.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              sliver: SliverToBoxAdapter(child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (_, t, child) => Opacity(opacity: t, child: child),
                child: GestureDetector(
                  onTap: _showJoinDialog,
                  child: Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: primary.withOpacity(0.35), width: 1.5),
                      boxShadow: softShadow(isDark),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 52, height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: primary.withOpacity(0.5), width: 1.5),
                        ),
                        child: Icon(Icons.add_rounded, color: primary, size: 26)),
                      const SizedBox(height: 12),
                      Text(l.t('add_subject'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: adaptiveText1(context))),
                      const SizedBox(height: 3),
                      Text(l.t('enter_teacher_code'), style: const TextStyle(fontSize: 12, color: C.text4)),
                    ]),
                  ),
                ),
              )),
            )
          else if (!provider.loading)
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ]),
      )),
    );
  }

  void _showContextMenu(Map<String, dynamic> cls) {
    final auth = context.read<AuthProvider>();
    final l = context.read<L10n>();
    final id = cls['id'] as int;
    final title = cls['title'] ?? '';
    final isPinned = _pinnedIds.contains(id);
    final colors = _grads[id % _grads.length];
    final coverImg = cls['cover_image'];

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const SizedBox(),
      transitionBuilder: (ctx, anim, __, ___) {
        return Stack(children: [
          // Backdrop dismiss
          GestureDetector(onTap: () => Navigator.pop(ctx)),
          // Menu
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
                  Clipboard.setData(ClipboardData(text: classCode(id)));
                  showToast(context, '${l.t('code_copied')}: ${classCode(id)}');
                },
                onShare: () {
                  Navigator.pop(ctx);
                  launchUrl(Uri.parse('chatra://class/${classCode(id)}'));
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
                  final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: Text(l.t('leave_class'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    content: Text(l.t('leave_class_sub')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.t('no'))),
                      ElevatedButton(onPressed: () => Navigator.pop(c, true), child: Text(l.t('leave_btn'))),
                    ],
                  ));
                  if (!mounted) return;
                  if (ok == true) {
                    await context.read<ClassesProvider>().leaveClass(id);
                    if (!mounted) return;
                    showToast(context, l.t('left_class'));
                  }
                },
                onMembers: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ClassDetailScreen(classId: id, initialTab: 3),
                  ));
                },
                onDelete: () async {
                  Navigator.pop(ctx);
                  final nameCtrl = TextEditingController();
                  final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: Text(l.t('delete_class'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(l.t('confirm_delete_hint'), style: const TextStyle(fontSize: 13, color: C.text4)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(hintText: title),
                      ),
                    ]),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.t('cancel'))),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: C.red),
                        onPressed: () => Navigator.pop(c, nameCtrl.text.trim() == title),
                        child: Text(l.t('delete')),
                      ),
                    ],
                  ));
                  if (!mounted) return;
                  if (ok == true) {
                    await context.read<ClassesProvider>().deleteClass(id);
                    if (!mounted) return;
                    showToast(context, l.t('class_deleted'));
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
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarScreen()));
  }

  // ── Join dialog ──────────────────────────────────────────────────────────────
  void _showJoinDialog() {
    final provider = context.read<ClassesProvider>();
    final l = context.read<L10n>();
    final controllers = List.generate(6, (_) => TextEditingController());
    final focusNodes  = List.generate(6, (_) => FocusNode());
    bool busy = false;

    showDialog(context: context, barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        String get6Code() => controllers.map((c) => c.text.toUpperCase()).join();

        void onKey(int i, String val) {
          if (val.length > 1) {
            final clean = val.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
            for (int j = 0; j < 6 && j < clean.length; j++) controllers[j].text = clean[j];
            focusNodes[5].requestFocus(); setS(() {}); return;
          }
          if (val.isNotEmpty && i < 5) focusNodes[i + 1].requestFocus();
          setS(() {});
        }

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: SingleChildScrollView(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: Alignment.topRight,
              child: GestureDetector(onTap: () => Navigator.pop(ctx),
                child: Container(width: 32, height: 32, decoration: BoxDecoration(color: adaptiveSurface2(context), shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 16, color: C.text4)))),
            const SizedBox(height: 4),
            Container(width: 68, height: 68, decoration: BoxDecoration(color: adaptivePrimaryLt(context), borderRadius: BorderRadius.circular(20)),
              child: Icon(Icons.lock_outline_rounded, color: Theme.of(context).colorScheme.primary, size: 32)),
            const SizedBox(height: 16),
            Text(l.t('join_class_title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(l.t('join_class_hint'),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: C.text4, height: 1.5)),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(6, (i) =>
              SizedBox(width: 44, height: 52, child: TextField(
                controller: controllers[i], focusNode: focusNodes[i],
                textAlign: TextAlign.center, maxLength: i == 0 ? 6 : 1,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true, fillColor: adaptiveSurface2(context),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)),
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (val) => onKey(i, val),
                onTap: () => controllers[i].selection = TextSelection(baseOffset: 0, extentOffset: controllers[i].text.length),
              )))),
            Builder(builder: (_) {
              final code = get6Code();
              if (code.length < 6) return const SizedBox.shrink();
              final found = provider.allClasses.where((c) => classCode(c['id']) == code).toList();
              if (found.isEmpty) return Padding(padding: const EdgeInsets.only(top: 16),
                child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: C.redLt, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [const Icon(Icons.error_outline, size: 16, color: C.red), const SizedBox(width: 8), Text(l.t('not_found'), style: const TextStyle(fontSize: 13, color: C.red, fontWeight: FontWeight.w500))])));
              final cls = found.first;
              final coverImg = cls['cover_image'];
              final teacherName = cls['teacher_name'] ?? '';
              return Padding(padding: const EdgeInsets.only(top: 16),
                child: Container(
                  decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2))),
                  clipBehavior: Clip.antiAlias,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(height: 80, width: double.infinity,
                      child: coverImg != null && coverImg.toString().startsWith('data:')
                          ? Builder(builder: (_) { try { return Image.memory(base64Decode(coverImg.toString().split(',').last), fit: BoxFit.cover, width: double.infinity); } catch (_) { return Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Theme.of(context).colorScheme.secondary, Theme.of(context).colorScheme.primary]))); } })
                          : coverImg != null
                              ? Image.network(coverImg, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Theme.of(context).colorScheme.secondary, Theme.of(context).colorScheme.primary]))))
                              : Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Theme.of(context).colorScheme.secondary, Theme.of(context).colorScheme.primary])))),
                    Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(cls['title'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (teacherName.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2),
                        child: Text(teacherName, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary))),
                    ])),
                  ])));
            }),
            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(l.t('cancel')))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: busy ? null : () async {
                  final code = get6Code();
                  if (code.length < 6) { showToast(context, l.t('enter_6_chars'), error: true); return; }
                  setS(() => busy = true);
                  final found = provider.allClasses.where((c) => classCode(c['id']) == code).toList();
                  if (found.isNotEmpty) {
                    final cls = found.first;
                    final id = cls['id'] as int;
                    final title = cls['title'] ?? '';
                    Navigator.pop(ctx);
                    await provider.joinClass(id);
                    if (!mounted) return;
                    showToast(context, '${l.t('joined_class')} $title');
                    Navigator.pushNamed(context, '/class', arguments: id);
                  } else { setS(() => busy = false); showToast(context, l.t('not_found'), error: true); }
                },
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(l.t('join_enter_class')))),
            ]),
          ])),
        );
      }),
    );
  }

  // ── Create class dialog ──────────────────────────────────────────────────────
  void _showCreateClass() {
    final provider = context.read<ClassesProvider>();
    final l = context.read<L10n>();
    final nameC = TextEditingController(), descC = TextEditingController(),
          teacherC = TextEditingController(), groupC = TextEditingController(), periodC = TextEditingController();
    String? coverB64;
    showDialog(context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(24, 20, 16, 0), child: Row(children: [
              Text(l.t('create_class_title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, size: 22), onPressed: () => Navigator.pop(ctx)),
            ])),
            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _fl3(l.t('class_cover')),
              GestureDetector(onTap: () async {
                final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
                if (img != null) { final bytes = await img.readAsBytes(); setS(() => coverB64 = 'data:image/jpeg;base64,${base64Encode(bytes)}'); }
              }, child: Container(height: 160, width: double.infinity,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3), width: 1.5), color: coverB64 != null ? null : adaptivePrimaryLt(context).withOpacity(0.3)),
                child: coverB64 != null
                    ? ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.memory(base64Decode(coverB64!.split(',').last), fit: BoxFit.cover, width: double.infinity))
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 50, height: 50, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.image_outlined, size: 26, color: Theme.of(context).colorScheme.primary)), const SizedBox(height: 10), Text(l.t('click_to_upload'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)), const Text('JPG, PNG', style: TextStyle(fontSize: 12, color: C.text4))]))),
              const SizedBox(height: 20),
              _fl3(l.t('class_name_required')), TextField(controller: nameC, decoration: InputDecoration(hintText: l.t('class_name_hint'))),
              const SizedBox(height: 16), _fl3(l.t('class_desc')), TextField(controller: descC, decoration: InputDecoration(hintText: l.t('class_desc_hint')), maxLines: 3),
              const SizedBox(height: 16), _fl3(l.t('period_label')), TextField(controller: periodC, decoration: InputDecoration(hintText: l.t('period_hint'))),
              const SizedBox(height: 16), _fl3(l.t('teacher_label')), TextField(controller: teacherC, decoration: InputDecoration(hintText: l.t('your_name_hint'))),
              const SizedBox(height: 16), _fl3(l.t('group')), TextField(controller: groupC, decoration: InputDecoration(hintText: l.t('group_hint'))),
              const SizedBox(height: 24),
            ]))),
            Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 20), child: Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text(l.t('cancel')), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () async {
                  if (nameC.text.trim().isEmpty) return;
                  try {
                    await provider.createClass(nameC.text.trim(), jsonEncode({
                      'type': 'class', 'description': descC.text.trim(), 'teacher_name': teacherC.text.trim(),
                      'group': groupC.text.trim(), 'period': periodC.text.trim(),
                      if (coverB64 != null) 'cover_image': coverB64,
                    }));
                    if (!mounted) return;
                    Navigator.pop(ctx);
                    showToast(context, l.t('class_created'));
                  } catch (_) {
                    if (!mounted) return;
                    showToast(context, l.t('error'), error: true);
                  }
                },
                child: Text(l.t('create')))),
            ])),
          ]),
        ),
      )));
  }

  Widget _fl3(String s) => Padding(padding: const EdgeInsets.only(bottom: 8),
    child: Text(s, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1)));
}

// ── Class Context Menu ────────────────────────────────────────────────────────

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
  final VoidCallback onMembers;
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
    required this.onMembers,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final bg2 = adaptiveSurface2(context);
    final primary = Theme.of(context).colorScheme.primary;
    final code = classCode(cls['id'] as int);
    final teacherName = cls['teacher_name'] as String? ?? '';

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 288,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: cardShadow(isDark),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [

            // ── Cover header ──
            SizedBox(height: 110, width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                coverImg != null && coverImg.toString().startsWith('data:')
                    ? Builder(builder: (_) { try { return Image.memory(base64Decode(coverImg.toString().split(',').last), fit: BoxFit.cover); } catch (_) { return Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors))); } })
                    : coverImg != null
                        ? Image.network(coverImg, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors))))
                        : Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight))),
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.55)],
                )))),
                Positioned(bottom: 10, left: 12,
                  child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (teacherName.isNotEmpty)
                  Positioned(bottom: 10, right: 12,
                    child: Text(teacherName, style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),

            // ── Code chip ──
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: primary.withOpacity(0.2)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.tag_rounded, size: 12, color: primary),
                    const SizedBox(width: 4),
                    Text(code, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: primary, letterSpacing: 2)),
                  ]),
                ),
                const Spacer(),
                _SmallAction(icon: Icons.copy_all_rounded, bg: primary.withOpacity(0.1), iconColor: primary, onTap: onCopyCode),
              ]),
            ),

            // ── Actions ──
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Column(children: [
                _ActionRow(
                  icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                  iconBg: primary.withOpacity(0.12),
                  iconColor: primary,
                  label: isPinned ? l.t('unpin_class') : l.t('pin_class'),
                  bg: bg2,
                  onTap: onTogglePin,
                ),
                if (isTeacher) ...[
                  const SizedBox(height: 6),
                  _ActionRow(
                    icon: Icons.group_rounded,
                    iconBg: C.green.withOpacity(0.12),
                    iconColor: C.green,
                    label: l.t('class_members'),
                    bg: bg2,
                    onTap: onMembers,
                  ),
                ],
              ]),
            ),

            // ── Danger zone ──
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: _ActionRow(
                icon: isTeacher ? Icons.delete_outline_rounded : Icons.logout_rounded,
                iconBg: C.red.withOpacity(0.12),
                iconColor: C.red,
                label: isTeacher ? l.t('delete_class') : l.t('leave_class'),
                bg: C.red.withOpacity(isDark ? 0.08 : 0.05),
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
  const _SmallAction({required this.icon, required this.bg, required this.iconColor, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 34, height: 34,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
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
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 17, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: labelColor))),
              Icon(Icons.chevron_right_rounded, size: 16, color: labelColor.withOpacity(0.35)),
            ]),
          ),
        ),
      ),
    );
  }
}


// ── Class Card ────────────────────────────────────────────────────────────────
// Extracted into its own StatelessWidget so it is NOT rebuilt when the parent
// HomeScreen rebuilds during SliverReorderableList drag operations.

class _ClassCard extends StatelessWidget {
  final Map<String, dynamic> cls;
  final int index;
  final List<Color> colors;
  final bool isPinned;
  final int lectureCount;
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
    required this.lectureCount,
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
    final coverImg = cls['cover_image'];
    final group    = cls['group'] ?? '';
    final teacherName = cls['teacher_name'] ?? '';
    final id = cls['id'] as int;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: cardShadow(isDark),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Cover image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: SizedBox(height: 168, width: double.infinity,
                child: Stack(fit: StackFit.expand, children: [
                  // Always-visible gradient — prevents grey flash when image remounts
                  Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight))),
                  if (coverImg != null && coverImg.toString().startsWith('data:'))
                    Builder(builder: (_) {
                      try { return Image.memory(base64Decode(coverImg.toString().split(',').last), fit: BoxFit.cover); }
                      catch (_) { return const SizedBox.shrink(); }
                    })
                  else if (coverImg != null)
                    CachedNetworkImage(
                      imageUrl: coverImg.toString(),
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                    ),
                  // Bottom gradient
                  Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    stops: const [0.5, 1.0],
                    colors: [Colors.transparent, Colors.black.withOpacity(0.45)],
                  )))),
                  // Teacher code chip
                  if (isTeacher)
                    Positioned(top: 10, left: 10, child: GestureDetector(
                      onTap: onCopyCode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.copy, size: 11, color: Colors.white60),
                          const SizedBox(width: 4),
                          Text(classCode(id), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2)),
                        ]),
                      ))),
                  // Pin icon
                  if (isPinned)
                    const Positioned(top: 10, right: 10, child: Icon(Icons.push_pin_rounded, color: Colors.white, size: 18)),
                  // Drag handle
                  Positioned(bottom: 8, right: 8,
                    child: ReorderableDragStartListener(
                      index: index,
                      child: SizedBox(width: 44, height: 44,
                        child: Center(child: Icon(Icons.drag_indicator_rounded, size: 20, color: Colors.white.withOpacity(0.5)))),
                    )),
                  // Lesson count badge
                  Positioned(bottom: 10, left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.48), borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.play_circle_outline_rounded, size: 13, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text('$lectureCount', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
                    )),
                ]),
              ),
            ),
            // Info section
            Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cls['title'] ?? '', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: adaptiveText1(context), height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (group.isNotEmpty) _MetaChip(label: group, icon: Icons.group_outlined, isDark: isDark),
                if (teacherName.isNotEmpty) _MetaChip(label: teacherName, icon: Icons.person_outline_rounded, isDark: isDark, color: Theme.of(context).colorScheme.primary),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: adaptivePrimaryLt(context), borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(openLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: Theme.of(context).colorScheme.primary),
                  ]),
                ),
                const Spacer(),
                if (isTeacher) _ActionBtn(
                  icon: Icons.delete_outline_rounded, color: C.text4, isDark: isDark,
                  onTap: () async {
                    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: Text(deleteLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(noLabel)),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: C.red),
                          onPressed: () => Navigator.pop(ctx, true), child: Text(deleteConfirmLabel)),
                      ],
                    ));
                    if (ok == true) await onDelete();
                  },
                ),
                if (!isTeacher) _ActionBtn(
                  icon: Icons.logout_rounded, color: C.text4, isDark: isDark,
                  onTap: () async {
                    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: Text(leaveLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                      content: Text(leaveSub),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(noLabel)),
                        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(leaveBtnLabel)),
                      ],
                    ));
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

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDark;
  const _HeaderBtn({required this.icon, required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(width: 42, height: 42,
      decoration: BoxDecoration(
        color: adaptiveSurface2(context),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.25)),
      ),
      child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 19)),
  );
}

class _MetaChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  final Color? color;
  const _MetaChip({required this.label, required this.icon, required this.isDark, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? C.text4;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.color, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(width: 34, height: 34,
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
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
            gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary.withOpacity(0.18), Theme.of(context).colorScheme.primary.withOpacity(0.06)]),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.menu_book_rounded, color: Theme.of(context).colorScheme.primary, size: 40)),
        const SizedBox(height: 22),
        Text(l.t('no_classes'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: adaptiveText1(context), letterSpacing: -0.4)),
        const SizedBox(height: 8),
        Text(isTeacher ? l.t('create_first_class') : l.t('enter_teacher_code'),
          style: const TextStyle(fontSize: 14, color: C.text4), textAlign: TextAlign.center),
        const SizedBox(height: 28),
        if (isTeacher) ...[
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(l.t('create_class')),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: onJoin,
            icon: const Icon(Icons.vpn_key_rounded, size: 16),
            label: Text(l.t('enter_code')),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
        ] else
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: onJoin,
            icon: const Icon(Icons.vpn_key_rounded, size: 18),
            label: Text(l.t('enter_code')),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
      ]),
    ));
  }
}

