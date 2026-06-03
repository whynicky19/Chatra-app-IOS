import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../providers/classes_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/class_utils.dart';
import '../../widgets/toast.dart';
import '../notifications/notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<ClassesProvider>();
    provider.addListener(_onProviderError);
    provider.loadJoined().then((_) => provider.load());
    provider.loadNotifBadge();
  }

  @override
  void dispose() {
    context.read<ClassesProvider>().removeListener(_onProviderError);
    super.dispose();
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

    return Scaffold(
      body: SafeArea(child: RefreshIndicator(
        color: C.teal,
        onRefresh: () => context.read<ClassesProvider>().load(),
        child: CustomScrollView(slivers: [

          // ── Header ──────────────────────────────────────────
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.t('classes'), style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w900,
                  color: C.teal, letterSpacing: -0.8, height: 1.1,
                )),
                const SizedBox(height: 2),
                Text(l.t('classes_sub'), style: const TextStyle(fontSize: 13, color: C.text4)),
              ])),
              if (auth.isTeacher) ...[
                _HeaderBtn(icon: Icons.vpn_key_rounded, onTap: _showJoinDialog, isDark: isDark),
                const SizedBox(width: 8),
                GestureDetector(onTap: _showCreateClass,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(
                      color: C.teal,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: tealGlow(opacity: 0.30),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(l.t('create_class'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    ]),
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
                      color: C.teal,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: tealGlow(opacity: 0.30),
                    ),
                    child: const Icon(Icons.vpn_key_rounded, color: Colors.white, size: 18))),
              ],
            ]),
          )),

          // ── Class cards ──────────────────────────────────────
          if (provider.loading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: C.teal, strokeWidth: 2.5)))
          else if (provider.classes.isEmpty)
            SliverFillRemaining(child: _EmptyState(isTeacher: auth.isTeacher, onCreate: _showCreateClass, onJoin: _showJoinDialog))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              sliver: SliverList(delegate: SliverChildBuilderDelegate((ctx, i) {
                final cls    = provider.classes[i];
                final id     = cls['id'] as int;
                final colors = _grads[id % _grads.length];
                final coverImg = cls['cover_image'];
                final teacherName = cls['teacher_name'] ?? '';
                final group  = cls['group'] ?? '';
                final count  = provider.lectureCount(id);

                return TweenAnimationBuilder<double>(
                  key: ValueKey(id),
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 380 + i * 55),
                  curve: Curves.easeOutCubic,
                  builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: child)),
                  child: GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/class', arguments: id),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: cardShadow(isDark),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // Cover
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                          child: SizedBox(height: 168, width: double.infinity,
                            child: Stack(fit: StackFit.expand, children: [
                              if (coverImg != null && coverImg.toString().startsWith('data:'))
                                Builder(builder: (_) { try { return Image.memory(base64Decode(coverImg.toString().split(',').last), fit: BoxFit.cover); } catch (_) { return Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors))); } })
                              else if (coverImg != null)
                                Image.network(coverImg, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors))))
                              else
                                Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight))),
                              // Bottom gradient for readability
                              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                stops: const [0.5, 1.0],
                                colors: [Colors.transparent, Colors.black.withOpacity(0.45)],
                              )))),
                              // Teacher code chip
                              if (auth.isTeacher)
                                Positioned(top: 10, left: 10, child: GestureDetector(
                                  onTap: () { Clipboard.setData(ClipboardData(text: classCode(id))); showToast(context, 'Code copied: ${classCode(id)}'); },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(8)),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.copy, size: 11, color: Colors.white60),
                                      const SizedBox(width: 4),
                                      Text(classCode(id), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2)),
                                    ]),
                                  ))),
                              // Lesson count badge (bottom-left)
                              Positioned(bottom: 10, left: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.48), borderRadius: BorderRadius.circular(8)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.play_circle_outline_rounded, size: 13, color: Colors.white70),
                                    const SizedBox(width: 4),
                                    Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                  ]),
                                )),
                            ]),
                          ),
                        ),
                        // Info section
                        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(cls['title'] ?? '', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: adaptiveText1(context), height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 8),
                          // Meta chips
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            if (group.isNotEmpty) _MetaChip(label: group, icon: Icons.group_outlined, isDark: isDark),
                            if (teacherName.isNotEmpty) _MetaChip(label: teacherName, icon: Icons.person_outline_rounded, isDark: isDark, color: C.teal),
                          ]),
                          const SizedBox(height: 12),
                          // Footer row
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(color: adaptiveTealLt(context), borderRadius: BorderRadius.circular(10)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Text('Открыть', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.teal)),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_forward_rounded, size: 14, color: C.teal),
                              ]),
                            ),
                            const Spacer(),
                            if (auth.isTeacher) _ActionBtn(
                              icon: Icons.delete_outline_rounded, color: C.text4, isDark: isDark,
                              onTap: () async {
                                final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  title: const Text('Удалить класс?', style: TextStyle(fontWeight: FontWeight.w800)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: C.red),
                                      onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
                                  ],
                                ));
                                if (!mounted) return;
                                if (ok == true) {
                                  await context.read<ClassesProvider>().deleteClass(id);
                                  if (!mounted) return;
                                  showToast(context, 'Deleted');
                                }
                              },
                            ),
                            if (!auth.isTeacher) _ActionBtn(
                              icon: Icons.logout_rounded, color: C.text4, isDark: isDark,
                              onTap: () async {
                                final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  title: const Text('Покинуть класс?', style: TextStyle(fontWeight: FontWeight.w800)),
                                  content: const Text('Вы сможете войти снова по коду.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
                                    ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Покинуть')),
                                  ],
                                ));
                                if (!mounted) return;
                                if (ok == true) {
                                  await context.read<ClassesProvider>().leaveClass(id);
                                  if (!mounted) return;
                                  showToast(context, 'Left class');
                                }
                              },
                            ),
                          ]),
                        ])),
                      ]),
                    ),
                  ),
                );
              }, childCount: provider.classes.length)),
            ),

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
                      border: Border.all(color: C.teal.withOpacity(0.35), width: 1.5),
                      boxShadow: softShadow(isDark),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 52, height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: C.teal.withOpacity(0.5), width: 1.5),
                        ),
                        child: const Icon(Icons.add_rounded, color: C.teal, size: 26)),
                      const SizedBox(height: 12),
                      Text('Добавить предмет', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: adaptiveText1(context))),
                      const SizedBox(height: 3),
                      const Text('Введите код от преподавателя', style: TextStyle(fontSize: 12, color: C.text4)),
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

  // ── Join dialog ──────────────────────────────────────────────────────────────
  void _showJoinDialog() {
    final provider = context.read<ClassesProvider>();
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
            Container(width: 68, height: 68, decoration: BoxDecoration(color: adaptiveTealLt(context), borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.lock_outline_rounded, color: C.teal, size: 32)),
            const SizedBox(height: 16),
            const Text('Войти в класс по коду', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('Введите 6-значный код класса, который вам дал преподаватель',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: C.text4, height: 1.5)),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(6, (i) =>
              SizedBox(width: 44, height: 52, child: TextField(
                controller: controllers[i], focusNode: focusNodes[i],
                textAlign: TextAlign.center, maxLength: i == 0 ? 6 : 1,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.teal),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true, fillColor: adaptiveSurface2(context),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.teal, width: 2)),
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
                  child: const Row(children: [Icon(Icons.error_outline, size: 16, color: C.red), SizedBox(width: 8), Text('Класс не найден', style: TextStyle(fontSize: 13, color: C.red, fontWeight: FontWeight.w500))])));
              final cls = found.first;
              final coverImg = cls['cover_image'];
              final teacherName = cls['teacher_name'] ?? '';
              return Padding(padding: const EdgeInsets.only(top: 16),
                child: Container(
                  decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.teal.withOpacity(0.2))),
                  clipBehavior: Clip.antiAlias,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(height: 80, width: double.infinity,
                      child: coverImg != null && coverImg.toString().startsWith('data:')
                          ? Builder(builder: (_) { try { return Image.memory(base64Decode(coverImg.toString().split(',').last), fit: BoxFit.cover, width: double.infinity); } catch (_) { return Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF006475), C.teal]))); } })
                          : coverImg != null
                              ? Image.network(coverImg, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF006475), C.teal]))))
                              : Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF006475), C.teal])))),
                    Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(cls['title'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (teacherName.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2),
                        child: Text(teacherName, style: const TextStyle(fontSize: 13, color: C.teal))),
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
                child: const Text('Отмена'))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: busy ? null : () async {
                  final code = get6Code();
                  if (code.length < 6) { showToast(context, 'Введите 6 символов', error: true); return; }
                  setS(() => busy = true);
                  final found = provider.allClasses.where((c) => classCode(c['id']) == code).toList();
                  if (found.isNotEmpty) {
                    final cls = found.first;
                    final id = cls['id'] as int;
                    final title = cls['title'] ?? '';
                    Navigator.pop(ctx);
                    await provider.joinClass(id);
                    if (!mounted) return;
                    showToast(context, 'Joined $title');
                    Navigator.pushNamed(context, '/class', arguments: id);
                  } else { setS(() => busy = false); showToast(context, 'Класс не найден', error: true); }
                },
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Войти в класс'))),
            ]),
          ])),
        );
      }),
    );
  }

  // ── Create class dialog ──────────────────────────────────────────────────────
  void _showCreateClass() {
    final provider = context.read<ClassesProvider>();
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
              const Text('Создать класс', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, size: 22), onPressed: () => Navigator.pop(ctx)),
            ])),
            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _fl3('ОБЛОЖКА КЛАССА'),
              GestureDetector(onTap: () async {
                final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
                if (img != null) { final bytes = await img.readAsBytes(); setS(() => coverB64 = 'data:image/jpeg;base64,${base64Encode(bytes)}'); }
              }, child: Container(height: 160, width: double.infinity,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: C.teal.withOpacity(0.3), width: 1.5), color: coverB64 != null ? null : adaptiveTealLt(context).withOpacity(0.3)),
                child: coverB64 != null
                    ? ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.memory(base64Decode(coverB64!.split(',').last), fit: BoxFit.cover, width: double.infinity))
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 50, height: 50, decoration: BoxDecoration(color: C.teal.withOpacity(0.15), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.image_outlined, size: 26, color: C.teal)), const SizedBox(height: 10), const Text('Нажмите для загрузки', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.teal)), const Text('JPG, PNG', style: TextStyle(fontSize: 12, color: C.text4))]))),
              const SizedBox(height: 20),
              _fl3('НАЗВАНИЕ КЛАССА *'), TextField(controller: nameC, decoration: const InputDecoration(hintText: 'Например: Математика 10А')),
              const SizedBox(height: 16), _fl3('ОПИСАНИЕ'), TextField(controller: descC, decoration: const InputDecoration(hintText: 'Краткое описание курса'), maxLines: 3),
              const SizedBox(height: 16), _fl3('ПЕРИОД'), TextField(controller: periodC, decoration: const InputDecoration(hintText: 'Например: 2024-2025')),
              const SizedBox(height: 16), _fl3('УЧИТЕЛЬ / ПРЕПОДАВАТЕЛЬ'), TextField(controller: teacherC, decoration: const InputDecoration(hintText: 'Ваше имя')),
              const SizedBox(height: 16), _fl3('ГРУППА'), TextField(controller: groupC, decoration: const InputDecoration(hintText: 'Например: ИСУ-21')),
              const SizedBox(height: 24),
            ]))),
            Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 20), child: Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена'), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)))),
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
                    showToast(context, 'Class created');
                  } catch (_) {
                    if (!mounted) return;
                    showToast(context, 'Error', error: true);
                  }
                },
                child: const Text('Создать'))),
            ])),
          ]),
        ),
      )));
  }

  Widget _fl3(String s) => Padding(padding: const EdgeInsets.only(bottom: 8),
    child: Text(s, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.teal, letterSpacing: 1)));
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
        border: Border.all(color: C.teal.withOpacity(0.25)),
      ),
      child: Icon(icon, color: C.teal, size: 19)),
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
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 88, height: 88,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [C.teal.withOpacity(0.18), C.teal.withOpacity(0.06)]),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.menu_book_rounded, color: C.teal, size: 40)),
      const SizedBox(height: 22),
      Text('Нет классов', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: adaptiveText1(context), letterSpacing: -0.4)),
      const SizedBox(height: 8),
      Text(isTeacher ? 'Создайте первый класс' : 'Введите код от преподавателя',
        style: const TextStyle(fontSize: 14, color: C.text4), textAlign: TextAlign.center),
      const SizedBox(height: 28),
      if (isTeacher) ...[
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Создать класс'),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        )),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          onPressed: onJoin,
          icon: const Icon(Icons.vpn_key_rounded, size: 16),
          label: const Text('Войти по коду'),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        )),
      ] else
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: onJoin,
          icon: const Icon(Icons.vpn_key_rounded, size: 18),
          label: const Text('Войти по коду'),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        )),
    ]),
  ));
}
