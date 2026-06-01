import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _posts = [];
  bool _loading = true;
  Set<int> _joinedClassIds = {};

  @override void initState() { super.initState(); _loadJoined().then((_) => _load()); }

  // ── Persistence for joined classes (keyed by userId) ──────────────────────
  String _prefsKey() {
    final uid = context.read<AuthProvider>().userId ?? 0;
    return 'joined_classes_$uid';
  }

  Future<void> _loadJoined() async {
    final uid = context.read<AuthProvider>().userId ?? 0;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('joined_classes_$uid') ?? [];
    if (mounted) setState(() => _joinedClassIds = list.map(int.parse).toSet());
  }

  Future<void> _saveJoined() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey(), _joinedClassIds.map((e) => e.toString()).toList());
  }

  Future<void> _joinClass(int id, String title) async {
    setState(() => _joinedClassIds.add(id));
    await _saveJoined();
    if (mounted) showToast(context, 'Joined $title');
  }

  // ── Data ──────────────────────────────────────────────────────────────────
  Future<void> _load() async {
    if (!mounted) return; setState(() => _loading = true);
    try { _posts = await context.read<ApiService>().getPosts(); } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _allClasses {
    return _posts.where((p) { try { return jsonDecode(p['body'])['type'] == 'class'; } catch (_) { return false; } })
      .map((p) { try { final b = jsonDecode(p['body']); return {...p as Map<String, dynamic>, ...b as Map<String, dynamic>, 'title': p['title']}; } catch (_) { return p as Map<String, dynamic>; } }).toList();
  }

  // Teachers see all their classes; students see only joined ones
  List<Map<String, dynamic>> get _classes {
    final auth = context.read<AuthProvider>();
    if (auth.isTeacher) return _allClasses;
    return _allClasses.where((c) => _joinedClassIds.contains(c['id'] as int)).toList();
  }

  int _lectureCount(int id) => _posts.where((p) => (p['title'] ?? '').startsWith('[LECTURE][$id]')).length;

  String _code(int id) { const c = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; var s = ''; var n = id * 1337 + 42; for (var i = 0; i < 6; i++) { s += c[n % c.length]; n = n ~/ c.length + id * 7; } return s.substring(0, 6); }

  static const _grads = [[Color(0xFF006475), Color(0xFF009AAF)], [Color(0xFF0C4A6E), Color(0xFF0369A1)], [Color(0xFF134E4A), Color(0xFF0D9488)], [Color(0xFF312E81), Color(0xFF4338CA)], [Color(0xFF1E3A5F), Color(0xFF2563EB)]];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Scaffold(
      body: SafeArea(child: RefreshIndicator(color: C.teal, onRefresh: _load, child: CustomScrollView(slivers: [
        // Header
        SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 16), child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.t('classes'), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: C.teal)),
            Text(l.t('classes_sub'), style: TextStyle(fontSize: 13, color: C.text4)),
          ])),
          if (auth.isTeacher)
            GestureDetector(onTap: () => _showCreateClass(),
              child: Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: C.teal, borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: C.teal.withOpacity(0.35), blurRadius: 10, offset: Offset(0, 4))]),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add, color: Colors.white, size: 18), SizedBox(width: 6), Text(l.t('create_class'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))])))
          else
            GestureDetector(onTap: _showJoinDialog,
              child: Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: C.teal, borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: C.teal.withOpacity(0.35), blurRadius: 10, offset: Offset(0, 4))]),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.vpn_key_rounded, color: Colors.white, size: 16), SizedBox(width: 6), Text(l.t('join_code'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))]))),
        ]))),

        // Class cards
        if (_loading) SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: C.teal, strokeWidth: 2.5)))
        else if (_classes.isEmpty) SliverFillRemaining(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 80, height: 80, decoration: BoxDecoration(gradient: LinearGradient(colors: [C.teal.withOpacity(0.15), C.teal.withOpacity(0.05)]), shape: BoxShape.circle),
            child: Icon(Icons.menu_book_rounded, color: C.teal, size: 36)),
          SizedBox(height: 20), Text('Нет классов', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: adaptiveText1(context))),
          SizedBox(height: 6), Text('Введите код от преподавателя', style: TextStyle(fontSize: 14, color: C.text4)),
          SizedBox(height: 20), GestureDetector(onTap: _showJoinDialog,
            child: Container(padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(color: C.teal, borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: C.teal.withOpacity(0.4), blurRadius: 12, offset: Offset(0, 4))]),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.vpn_key_rounded, color: Colors.white, size: 18), SizedBox(width: 8), Text('Войти по коду', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))]))),
        ])))
        else SliverPadding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0), sliver: SliverList(delegate: SliverChildBuilderDelegate((ctx, i) {
          final cls = _classes[i];
          final id = cls['id'] as int;
          final colors = _grads[id % _grads.length];
          final coverImg = cls['cover_image'];
          final teacherName = cls['teacher_name'] ?? '';
          final group = cls['group'] ?? '';

          return GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/class', arguments: id),
            child: Container(
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.15))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Cover image
                ClipRRect(borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                  child: SizedBox(height: 160, width: double.infinity, child: Stack(fit: StackFit.expand, children: [
                    if (coverImg != null && coverImg.toString().startsWith('data:'))
                      Builder(builder: (_) { try { return Image.memory(base64Decode(coverImg.toString().split(',').last), fit: BoxFit.cover); } catch (_) { return Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors))); } })
                    else if (coverImg != null)
                      Image.network(coverImg, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors))))
                    else
                      Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight))),
                    // Code chip (teachers only)
                    if (auth.isTeacher)
                      Positioned(top: 10, left: 10, child: GestureDetector(
                        onTap: () { Clipboard.setData(ClipboardData(text: _code(id))); showToast(context, 'Code copied: ${_code(id)}'); },
                        child: Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.copy, size: 12, color: Colors.white70), SizedBox(width: 4), Text(_code(id), style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2))])))),
                    if (auth.isTeacher)
                      Positioned(top: 10, right: 10, child: GestureDetector(
                        onTap: () => Navigator.pushNamed(context, '/class', arguments: id),
                        child: Container(width: 34, height: 34, decoration: BoxDecoration(color: Colors.black38, shape: BoxShape.circle), child: Icon(Icons.edit, size: 16, color: Colors.white70)))),
                  ]))),
                // Body
                Padding(padding: EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(cls['title'] ?? '', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis)),
                    Container(width: 36, height: 36, decoration: BoxDecoration(color: adaptiveTealLt(context), borderRadius: BorderRadius.circular(10)),
                      child: Icon(Icons.menu_book, size: 18, color: C.teal)),
                  ]),
                  if (group.isNotEmpty) Padding(padding: EdgeInsets.only(top: 4), child: Text(group, style: TextStyle(fontSize: 13, color: C.text4))),
                  if (teacherName.isNotEmpty) Padding(padding: EdgeInsets.only(top: 4), child: Row(children: [Icon(Icons.person_outline, size: 14, color: C.teal), SizedBox(width: 4), Text(teacherName, style: TextStyle(fontSize: 13, color: C.text3, fontWeight: FontWeight.w500))])),
                  Padding(padding: EdgeInsets.only(top: 4), child: Row(children: [Icon(Icons.access_time, size: 14, color: C.text4), SizedBox(width: 4), Text('${_lectureCount(id)} lessons', style: TextStyle(fontSize: 13, color: C.text4))])),
                  SizedBox(height: 10),
                  Row(children: [
                    Text('Open course →', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.teal, fontStyle: FontStyle.italic)),
                    Spacer(),
                    if (auth.isTeacher) GestureDetector(
                      onTap: () async {
                        final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                          title: Text('Удалить класс?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Нет')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Да'))],
                        ));
                        if (ok == true) { try { await context.read<ApiService>().deletePost(id); _load(); showToast(context, 'Deleted'); } catch (_) {} }
                      },
                      child: Container(width: 34, height: 34, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.3))),
                        child: Icon(Icons.delete_outline, size: 18, color: C.text4))),
                    // Leave button for students
                    if (!auth.isTeacher) GestureDetector(
                      onTap: () async {
                        final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                          title: Text('Покинуть класс?'),
                          content: Text('Вы сможете войти снова по коду.'),
                          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Нет')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Покинуть'))],
                        ));
                        if (ok == true) {
                          setState(() => _joinedClassIds.remove(id));
                          await _saveJoined();
                          showToast(context, 'Left class');
                        }
                      },
                      child: Container(width: 34, height: 34, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.3))),
                        child: Icon(Icons.logout, size: 18, color: C.text4))),
                  ]),
                ])),
              ]),
            ),
          );
        }, childCount: _classes.length))),
        // "Add new subject" card — students only
        if (!auth.isTeacher && !_loading && _classes.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 90),
            sliver: SliverToBoxAdapter(child: GestureDetector(
              onTap: _showJoinDialog,
              child: Container(
                margin: EdgeInsets.only(top: 8),
                padding: EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: C.teal.withOpacity(0.35), width: 1.5, strokeAlign: BorderSide.strokeAlignCenter),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle,
                    border: Border.all(color: C.teal.withOpacity(0.4), width: 2, strokeAlign: BorderSide.strokeAlignCenter)),
                    child: Icon(Icons.add, color: C.teal, size: 28)),
                  SizedBox(height: 14),
                  Text('Добавить предмет', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: adaptiveText1(context))),
                  SizedBox(height: 4),
                  Text('Персонализируйте своё обучение', style: TextStyle(fontSize: 13, color: C.text4)),
                ]),
              ),
            )),
          )
        else if (!_loading)
          SliverToBoxAdapter(child: SizedBox(height: 90)),
      ]))),
    );
  }

  void _showJoinDialog() {
    final controllers = List.generate(6, (_) => TextEditingController());
    final focusNodes = List.generate(6, (_) => FocusNode());
    bool busy = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        String get6Code() => controllers.map((c) => c.text.toUpperCase()).join();

        void onKey(int i, String val) {
          if (val.length > 1) {
            // Handle paste
            final clean = val.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
            for (int j = 0; j < 6 && j < clean.length; j++) {
              controllers[j].text = clean[j];
            }
            focusNodes[5].requestFocus();
            setS(() {});
            return;
          }
          if (val.isNotEmpty && i < 5) focusNodes[i + 1].requestFocus();
          setS(() {});
        }

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          insetPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Close button
              Align(alignment: Alignment.topRight,
                child: GestureDetector(onTap: () => Navigator.pop(ctx),
                  child: Container(width: 32, height: 32, decoration: BoxDecoration(color: adaptiveSurface2(context), shape: BoxShape.circle),
                    child: Icon(Icons.close, size: 16, color: C.text4)))),
              SizedBox(height: 4),
              // Lock icon
              Container(width: 68, height: 68, decoration: BoxDecoration(color: adaptiveTealLt(context), borderRadius: BorderRadius.circular(20)),
                child: Icon(Icons.lock_outline_rounded, color: C.teal, size: 32)),
              SizedBox(height: 16),
              Text('Войти в класс по коду', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              SizedBox(height: 8),
              Text('Введите 6-значный код класса, который вам дал преподаватель',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: C.text4, height: 1.5)),
              SizedBox(height: 24),
              // 6 OTP boxes
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(6, (i) =>
                SizedBox(width: 44, height: 52,
                  child: TextField(
                    controller: controllers[i],
                    focusNode: focusNodes[i],
                    textAlign: TextAlign.center,
                    maxLength: i == 0 ? 6 : 1, // Allow paste on first box
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: C.teal),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: adaptiveSurface2(context),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: C.teal, width: 2)),
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (val) => onKey(i, val),
                    onTap: () => controllers[i].selection = TextSelection(baseOffset: 0, extentOffset: controllers[i].text.length),
                  )))),

              // ── Class preview (shows when code matches) ──
              Builder(builder: (_) {
                final code = get6Code();
                if (code.length < 6) return SizedBox.shrink();
                final found = _allClasses.where((c) => _code(c['id']) == code).toList();
                if (found.isEmpty) return Padding(padding: EdgeInsets.only(top: 16),
                  child: Container(padding: EdgeInsets.all(12), decoration: BoxDecoration(color: C.redLt, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [Icon(Icons.error_outline, size: 16, color: C.red), SizedBox(width: 8),
                      Text('Класс не найден', style: TextStyle(fontSize: 13, color: C.red, fontWeight: FontWeight.w500))])));
                final cls = found.first;
                final coverImg = cls['cover_image'];
                final teacherName = cls['teacher_name'] ?? '';
                return Padding(padding: EdgeInsets.only(top: 16),
                  child: Container(
                    decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.teal.withOpacity(0.2))),
                    clipBehavior: Clip.antiAlias,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Cover
                      SizedBox(height: 80, width: double.infinity,
                        child: coverImg != null && coverImg.toString().startsWith('data:')
                            ? Builder(builder: (_) { try { return Image.memory(base64Decode(coverImg.toString().split(',').last), fit: BoxFit.cover, width: double.infinity); } catch (_) { return Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF006475), C.teal]))); } })
                            : coverImg != null
                                ? Image.network(coverImg, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF006475), C.teal]))))
                                : Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF006475), C.teal])))),
                      Padding(padding: EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(cls['title'] ?? '', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (teacherName.isNotEmpty) Padding(padding: EdgeInsets.only(top: 2),
                          child: Text(teacherName, style: TextStyle(fontSize: 13, color: C.teal))),
                      ])),
                    ])));
              }),

              SizedBox(height: 24),
              Divider(height: 1),
              SizedBox(height: 20),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
                  child: Text('Отмена'))),
                SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
                  onPressed: busy ? null : () async {
                    final code = get6Code();
                    if (code.length < 6) { showToast(context, 'Введите 6 символов', error: true); return; }
                    setS(() => busy = true);
                    final found = _allClasses.where((c) => _code(c['id']) == code).toList();
                    if (found.isNotEmpty) {
                      final cls = found.first;
                      final id = cls['id'] as int;
                      Navigator.pop(ctx);
                      await _joinClass(id, cls['title'] ?? '');
                      if (mounted) Navigator.pushNamed(context, '/class', arguments: id);
                    } else {
                      setS(() => busy = false);
                      showToast(context, 'Класс не найден', error: true);
                    }
                  },
                  child: busy
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Войти в класс'))),
              ]),
            ]),
          ),
        );
      }),
    );
  }

  void _showCreateClass() {
    final nameC = TextEditingController(), descC = TextEditingController(), teacherC = TextEditingController(), groupC = TextEditingController(), periodC = TextEditingController();
    String? coverB64;
    showDialog(context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: EdgeInsets.all(20),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: Column(children: [
            Padding(padding: EdgeInsets.fromLTRB(24, 20, 16, 0), child: Row(children: [
              Text('Создать класс', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Spacer(),
              IconButton(icon: Icon(Icons.close, size: 22), onPressed: () => Navigator.pop(ctx)),
            ])),
            Expanded(child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(24, 16, 24, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _fieldLabel3('ОБЛОЖКА КЛАССА'),
              GestureDetector(onTap: () async {
                final picker = ImagePicker();
                final img = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
                if (img != null) { final bytes = await img.readAsBytes(); setS(() => coverB64 = 'data:image/jpeg;base64,${base64Encode(bytes)}'); }
              }, child: Container(height: 160, width: double.infinity,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: C.teal.withOpacity(0.3), width: 1.5, strokeAlign: BorderSide.strokeAlignCenter), color: coverB64 != null ? null : adaptiveTealLt(context).withOpacity(0.3)),
                child: coverB64 != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.memory(base64Decode(coverB64!.split(',').last), fit: BoxFit.cover, width: double.infinity))
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 50, height: 50, decoration: BoxDecoration(color: C.teal.withOpacity(0.15), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.image_outlined, size: 26, color: C.teal)), SizedBox(height: 10), Text('Нажмите для загрузки', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.teal)), Text('JPG, PNG', style: TextStyle(fontSize: 12, color: C.text4))]))),
              SizedBox(height: 20),
              _fieldLabel3('НАЗВАНИЕ КЛАССА *'), TextField(controller: nameC, decoration: InputDecoration(hintText: 'Например: Математика 10А')),
              SizedBox(height: 16), _fieldLabel3('ОПИСАНИЕ'), TextField(controller: descC, decoration: InputDecoration(hintText: 'Краткое описание курса'), maxLines: 3),
              SizedBox(height: 16), _fieldLabel3('ПЕРИОД'), TextField(controller: periodC, decoration: InputDecoration(hintText: 'Например: 2024-2025')),
              SizedBox(height: 16), _fieldLabel3('УЧИТЕЛЬ / ПРЕПОДАВАТЕЛЬ'), TextField(controller: teacherC, decoration: InputDecoration(hintText: 'Ваше имя')),
              SizedBox(height: 16), _fieldLabel3('ГРУППА'), TextField(controller: groupC, decoration: InputDecoration(hintText: 'Например: ИСУ-21')),
              SizedBox(height: 24),
            ]))),
            Padding(padding: EdgeInsets.fromLTRB(24, 8, 24, 20), child: Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text('Отмена'), style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)))),
              SizedBox(width: 12),
              Expanded(child: ElevatedButton(onPressed: () async {
                if (nameC.text.trim().isEmpty) return;
                try {
                  await context.read<ApiService>().createPost(nameC.text.trim(), jsonEncode({
                    'type': 'class', 'description': descC.text.trim(), 'teacher_name': teacherC.text.trim(), 'group': groupC.text.trim(), 'period': periodC.text.trim(),
                    if (coverB64 != null) 'cover_image': coverB64,
                  }));
                  Navigator.pop(ctx); _load(); showToast(context, 'Class created');
                } catch (_) { showToast(context, 'Error', error: true); }
              }, child: Text('Создать'), style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)))),
            ])),
          ]),
        ),
      )));
  }

  Widget _fieldLabel3(String s) => Padding(padding: EdgeInsets.only(bottom: 8), child: Text(s, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.teal, letterSpacing: 1)));
}