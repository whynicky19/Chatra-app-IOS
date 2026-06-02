import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class AiScreen extends StatefulWidget {
  const AiScreen({super.key});
  @override State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> with TickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, String>> _msgs = [];
  bool _loading = false;
  late AnimationController _pulseCtrl;
  late AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: Duration(seconds: 2))..repeat(reverse: true);
    _fadeCtrl = AnimationController(vsync: this, duration: Duration(milliseconds: 600))..forward();
  }
  @override void dispose() { _pulseCtrl.dispose(); _fadeCtrl.dispose(); super.dispose(); }

  List<Map<String, dynamic>> _tips(L10n l) => [
    {'icon': Icons.menu_book_rounded, 'text': l.t('tip_explain')},
    {'icon': Icons.lightbulb_outline_rounded, 'text': l.t('tip_concepts')},
    {'icon': Icons.assignment_outlined, 'text': l.t('tip_help')},
    {'icon': Icons.warning_amber_rounded, 'text': l.t('tip_mistakes')},
  ];

  void _send([String? override]) async {
    final text = override ?? _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    HapticFeedback.lightImpact();
    setState(() { _msgs.add({'role': 'user', 'text': text}); _loading = true; });
    _ctrl.clear();
    _scrollDown();
    try {
      final api = context.read<ApiService>();
      final l = context.read<L10n>();
      final sysLang = l.lang == 'KZ' ? 'казахском' : l.lang == 'EN' ? 'английском' : 'русском';
      final apiMsgs = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'Ты AI-ассистент образовательной платформы Chatra. Отвечай на $sysLang языке.'},
        ..._msgs.map((m) => {'role': m['role']!, 'content': m['text']!}),
      ];
      final data = await api.aiChat(apiMsgs);
      setState(() => _msgs.add({'role': 'assistant', 'text': data['content'] ?? l.t('no_answer')}));
    } catch (e) {
      final l = context.read<L10n>();
      setState(() => _msgs.add({'role': 'assistant', 'text': e.toString().contains('503') ? l.t('ai_not_configured') : l.t('connection_error')}));
    }
    setState(() => _loading = false);
    _scrollDown();
  }

  void _scrollDown() {
    Future.delayed(Duration(milliseconds: 100), () { if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Duration(milliseconds: 300), curve: Curves.easeOut); });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final l = context.watch<L10n>();

    return Scaffold(
      body: Column(children: [
        // Header
        SafeArea(bottom: false, child: Container(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [surface, isDark ? Color(0xFF0D1A1E) : Color(0xFFF0FAFB)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          ),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(
              gradient: LinearGradient(colors: [C.teal.withOpacity(0.25), C.tealDk.withOpacity(0.1)]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: C.teal.withOpacity(0.15), blurRadius: 10)]),
              child: Icon(Icons.auto_awesome, color: C.teal, size: 22)),
            SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.t('ai_assistant'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(l.t('ai_ask_anything'), style: TextStyle(fontSize: 12, color: C.text4)),
            ]),
            Spacer(),
            if (_msgs.isNotEmpty) GestureDetector(
              onTap: () => setState(() => _msgs.clear()),
              child: Container(padding: EdgeInsets.all(8), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.delete_outline, color: C.text4, size: 18))),
            SizedBox(width: 8),
            Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(gradient: LinearGradient(colors: [C.green.withOpacity(0.15), C.green.withOpacity(0.05)]), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 6, height: 6, decoration: BoxDecoration(color: C.green, shape: BoxShape.circle)), SizedBox(width: 4), Text(l.t('online'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.green))])),
          ]),
        )),
        // Body
        Expanded(child: Container(
          decoration: BoxDecoration(
            gradient: isDark ? null : LinearGradient(colors: [Color(0xFFF0FAFB), Color(0xFFF5F7F8)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
          child: _msgs.isEmpty ? _emptyState(isDark, l) : _messageList(isDark),
        )),
        // Input
        Container(
          padding: EdgeInsets.fromLTRB(14, 10, 14, 90),
          decoration: BoxDecoration(color: surface, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: Offset(0, -2))]),
          child: Row(children: [
            Expanded(child: Container(
              decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
              child: TextField(controller: _ctrl,
                decoration: InputDecoration(hintText: l.t('send_msg'), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
                onSubmitted: (_) => _send(), maxLines: 4, minLines: 1, onChanged: (_) => setState(() {})))),
            SizedBox(width: 10),
            GestureDetector(onTap: _send,
              child: AnimatedContainer(duration: Duration(milliseconds: 200), width: 48, height: 48,
                decoration: BoxDecoration(
                  gradient: _ctrl.text.trim().isNotEmpty && !_loading ? LinearGradient(colors: [C.teal, C.tealDk]) : null,
                  color: _ctrl.text.trim().isNotEmpty || _loading ? null : adaptiveSurface2(context),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: _ctrl.text.trim().isNotEmpty ? [BoxShadow(color: C.teal.withOpacity(0.4), blurRadius: 14, offset: Offset(0, 4))] : null),
                child: Icon(_loading ? Icons.hourglass_top : Icons.send_rounded, color: _ctrl.text.trim().isNotEmpty && !_loading ? Colors.white : C.text4, size: 20))),
          ]),
        ),
      ]),
    );
  }

  Widget _emptyState(bool isDark, L10n l) {
    final tips = _tips(l);
    return FadeTransition(opacity: _fadeCtrl, child: Center(child: SingleChildScrollView(padding: EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) {
        final v = _pulseCtrl.value;
        return Container(width: 100, height: 100,
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [C.teal.withOpacity(0.2 + v * 0.08), C.teal.withOpacity(0.03)], radius: 0.7),
            boxShadow: [BoxShadow(color: C.teal.withOpacity(0.1 + v * 0.05), blurRadius: 30, spreadRadius: 5)]),
          child: Icon(Icons.auto_awesome, color: C.teal, size: 44));
      }),
      SizedBox(height: 24),
      Text(l.t('ready_help'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      SizedBox(height: 8),
      Text(l.t('ask_ai'), style: TextStyle(fontSize: 15, color: C.teal, fontWeight: FontWeight.w500)),
      SizedBox(height: 32),
      ...tips.map((t) => Padding(padding: EdgeInsets.only(bottom: 10),
        child: GestureDetector(onTap: () => _send(t['text'] as String),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.teal.withOpacity(0.1)),
            ),
            child: Row(children: [
              Container(width: 36, height: 36,
                decoration: BoxDecoration(color: C.teal.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                child: Icon(t['icon'] as IconData, size: 18, color: C.teal)),
              SizedBox(width: 12),
              Expanded(child: Text(t['text'] as String, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
              Icon(Icons.arrow_forward_ios, size: 14, color: C.text4),
            ]),
          ),
        ),
      )),
    ]))));
  }

  Widget _messageList(bool isDark) {
    return ListView.builder(
      controller: _scroll, padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _msgs.length + (_loading ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _msgs.length) return _typingIndicator();
        final m = _msgs[i]; final isUser = m['role'] == 'user';

        if (isUser) return TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1), duration: Duration(milliseconds: 300),
          builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(20 * (1 - t), 0), child: child)),
          child: Padding(padding: EdgeInsets.only(bottom: 16), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Flexible(child: Container(padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [C.teal, C.tealDk], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(22), topRight: Radius.circular(22), bottomLeft: Radius.circular(22), bottomRight: Radius.circular(6)),
                boxShadow: [BoxShadow(color: C.teal.withOpacity(0.25), blurRadius: 14, offset: Offset(0, 5))]),
              child: Text(m['text'] ?? '', style: TextStyle(fontSize: 15, color: Colors.white, height: 1.5))))])));

        return TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1), duration: Duration(milliseconds: 300),
          builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(-20 * (1 - t), 0), child: child)),
          child: Padding(padding: EdgeInsets.only(bottom: 20), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 34, height: 34, margin: EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [C.teal.withOpacity(0.2), C.tealDk.withOpacity(0.1)]),
                borderRadius: BorderRadius.circular(11),
                boxShadow: [BoxShadow(color: C.teal.withOpacity(0.1), blurRadius: 8)]),
              child: Icon(Icons.auto_awesome, size: 16, color: C.teal)),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.teal)),
              SizedBox(height: 4),
              Container(padding: EdgeInsets.all(14), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.04), blurRadius: 10, offset: Offset(0, 2))]),
                child: SelectableText(m['text'] ?? '', style: TextStyle(fontSize: 15, height: 1.7))),
            ])),
          ])));
      },
    );
  }

  Widget _typingIndicator() => Padding(padding: EdgeInsets.only(bottom: 16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(width: 34, height: 34, decoration: BoxDecoration(gradient: LinearGradient(colors: [C.teal.withOpacity(0.2), C.tealDk.withOpacity(0.1)]), borderRadius: BorderRadius.circular(11)),
      child: Icon(Icons.auto_awesome, size: 16, color: C.teal)),
    SizedBox(width: 12),
    Container(padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
      child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => _Dot(delay: i * 200)))),
  ]));
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});
  @override State<_Dot> createState() => _DotState();
}
class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: Duration(milliseconds: 600))..repeat(reverse: true); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, __) => Container(width: 8, height: 8, margin: EdgeInsets.symmetric(horizontal: 3),
    decoration: BoxDecoration(color: C.teal.withOpacity(0.3 + _c.value * 0.7), shape: BoxShape.circle)));
}
