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
  late AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: Duration(seconds: 2))..repeat(reverse: true);
    _fadeCtrl = AnimationController(vsync: this, duration: Duration(milliseconds: 700))..forward();
    _shimmerCtrl = AnimationController(vsync: this, duration: Duration(seconds: 3))..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    _shimmerCtrl.dispose();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _tips(L10n l) => [
    {'icon': Icons.menu_book_rounded,         'text': l.t('tip_explain')},
    {'icon': Icons.lightbulb_outline_rounded, 'text': l.t('tip_concepts')},
    {'icon': Icons.assignment_outlined,       'text': l.t('tip_help')},
    {'icon': Icons.warning_amber_rounded,     'text': l.t('tip_mistakes')},
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
    Future.delayed(Duration(milliseconds: 100), () {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Duration(milliseconds: 350), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final l = context.watch<L10n>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(children: [
        _buildHeader(isDark, surface, l),
        Expanded(child: Container(
          decoration: BoxDecoration(
            gradient: isDark ? null : LinearGradient(
              colors: [Color(0xFFEEF8FA), Color(0xFFF4F7F9)],
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
            ),
          ),
          child: _msgs.isEmpty ? _emptyState(isDark, l) : _messageList(isDark),
        )),
        _buildInput(surface, l),
      ]),
    );
  }

  Widget _buildHeader(bool isDark, Color surface, L10n l) {
    return SafeArea(bottom: false, child: Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: surface,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 12, offset: Offset(0, 2))],
      ),
      child: Row(children: [
        // App logo
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: C.teal.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: EdgeInsets.all(2),
          child: Image.asset('assets/logo.png', fit: BoxFit.contain),
        ),
        SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.t('ai_assistant'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          SizedBox(height: 2),
          Row(children: [
            AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) => Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                color: C.green.withOpacity(0.5 + _pulseCtrl.value * 0.5),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: C.green.withOpacity(0.3 + _pulseCtrl.value * 0.2), blurRadius: 4)],
              ),
            )),
            SizedBox(width: 5),
            Text(l.t('online'), style: TextStyle(fontSize: 12, color: C.green, fontWeight: FontWeight.w600)),
            SizedBox(width: 8),
            Text('·', style: TextStyle(color: C.text4)),
            SizedBox(width: 8),
            Text(l.t('ai_ask_anything'), style: TextStyle(fontSize: 12, color: C.text4)),
          ]),
        ])),
        if (_msgs.isNotEmpty) GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            showDialog(context: context, builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Очистить чат?', style: TextStyle(fontWeight: FontWeight.w800)),
              content: Text('История переписки будет удалена', style: TextStyle(color: C.text4)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Отмена', style: TextStyle(color: C.text4))),
                TextButton(onPressed: () { Navigator.pop(ctx); setState(() => _msgs.clear()); }, child: Text('Удалить', style: TextStyle(color: C.red, fontWeight: FontWeight.w700))),
              ],
            ));
          },
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: C.teal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.delete_outline_rounded, color: C.teal, size: 19),
          ),
        ),
      ]),
    ));
  }

  Widget _emptyState(bool isDark, L10n l) {
    final tips = _tips(l);
    return FadeTransition(
      opacity: _fadeCtrl,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 32, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Logo with pulse ring
          AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) {
            final v = _pulseCtrl.value;
            return Stack(alignment: Alignment.center, children: [
              Container(width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: C.teal.withOpacity(0.04 + v * 0.04),
                )),
              Container(width: 96, height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: C.teal.withOpacity(0.07 + v * 0.05),
                  boxShadow: [BoxShadow(color: C.teal.withOpacity(0.12 + v * 0.08), blurRadius: 28, spreadRadius: 2)],
                )),
              Container(width: 88, height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? C.darkSurface : Colors.white,
                  boxShadow: [BoxShadow(color: C.teal.withOpacity(0.18), blurRadius: 20, offset: Offset(0, 4))],
                ),
                padding: EdgeInsets.all(6),
                child: Image.asset('assets/logo.png', fit: BoxFit.contain),
              ),
            ]);
          }),
          SizedBox(height: 24),
          Text(l.t('ready_help'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [C.teal.withOpacity(0.12), C.teal.withOpacity(0.06)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(l.t('ask_ai'), style: TextStyle(fontSize: 13, color: C.teal, fontWeight: FontWeight.w600)),
          ),
          SizedBox(height: 28),
          // Tip cards — all teal
          ...tips.asMap().entries.map((entry) {
            final i = entry.key;
            final t = entry.value;
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 400 + i * 80),
              curve: Curves.easeOutCubic,
              builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child)),
              child: GestureDetector(
                onTap: () => _send(t['text'] as String),
                child: Container(
                  margin: EdgeInsets.only(bottom: 10),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark ? C.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: C.teal.withOpacity(0.18), width: 1.5),
                    boxShadow: [BoxShadow(color: C.teal.withOpacity(isDark ? 0.04 : 0.07), blurRadius: 12, offset: Offset(0, 3))],
                  ),
                  child: Row(children: [
                    Container(width: 38, height: 38,
                      decoration: BoxDecoration(color: C.teal.withOpacity(0.10), borderRadius: BorderRadius.circular(11)),
                      child: Icon(t['icon'] as IconData, size: 18, color: C.teal)),
                    SizedBox(width: 12),
                    Expanded(child: Text(t['text'] as String, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3))),
                    Container(width: 28, height: 28,
                      decoration: BoxDecoration(color: C.teal.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.arrow_forward_rounded, size: 15, color: C.teal)),
                  ]),
                ),
              ),
            );
          }),
        ]),
      ),
    );
  }

  Widget _messageList(bool isDark) {
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
      itemCount: _msgs.length + (_loading ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _msgs.length) return _typingIndicator();
        final m = _msgs[i];
        final isUser = m['role'] == 'user';
        final isLast = i == _msgs.length - 1;

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(isUser ? 16 * (1 - t) : -16 * (1 - t), 6 * (1 - t)), child: child),
          ),
          child: isUser ? _userMessage(m['text'] ?? '', isLast) : _aiMessage(m['text'] ?? '', isDark, isLast),
        );
      },
    );
  }

  Widget _userMessage(String text, bool isLast) {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';
    return Padding(
      padding: EdgeInsets.only(bottom: 16, left: 48),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [C.teal, C.tealDk], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(22), topRight: Radius.circular(22),
              bottomLeft: Radius.circular(22), bottomRight: Radius.circular(6),
            ),
            boxShadow: [BoxShadow(color: C.teal.withOpacity(0.28), blurRadius: 16, offset: Offset(0, 5))],
          ),
          child: Text(text, style: TextStyle(fontSize: 15, color: Colors.white, height: 1.5)),
        ),
        SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(timeStr, style: TextStyle(fontSize: 10, color: C.text4)),
          SizedBox(width: 4),
          Icon(Icons.done_all_rounded, size: 13, color: C.teal),
        ]),
      ]),
    );
  }

  Widget _aiMessage(String text, bool isDark, bool isLast) {
    return Padding(
      padding: EdgeInsets.only(bottom: 20, right: 24),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // App logo as AI avatar
        Container(
          width: 44, height: 44,
          margin: EdgeInsets.only(top: 2, right: 10),
          decoration: BoxDecoration(
            color: isDark ? C.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: C.teal.withOpacity(0.2), width: 1.5),
            boxShadow: [BoxShadow(color: C.teal.withOpacity(0.1), blurRadius: 10, offset: Offset(0, 2))],
          ),
          padding: EdgeInsets.all(2),
          child: Image.asset('assets/logo.png', fit: BoxFit.contain),
        ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: EdgeInsets.only(left: 2, bottom: 5),
            child: Text('Chatra AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.teal, letterSpacing: 0.2))),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? C.darkSurface : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(6), topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20),
              ),
              border: Border.all(color: C.teal.withOpacity(isDark ? 0.12 : 0.08)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.05), blurRadius: 12, offset: Offset(0, 3))],
            ),
            child: SelectableText(text, style: TextStyle(fontSize: 15, height: 1.7, letterSpacing: 0.1)),
          ),
        ])),
      ]),
    );
  }

  Widget _typingIndicator() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(bottom: 16, right: 24),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44, height: 44,
          margin: EdgeInsets.only(top: 2, right: 10),
          decoration: BoxDecoration(
            color: isDark ? C.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: C.teal.withOpacity(0.2), width: 1.5),
            boxShadow: [BoxShadow(color: C.teal.withOpacity(0.1), blurRadius: 10)],
          ),
          padding: EdgeInsets.all(2),
          child: Image.asset('assets/logo.png', fit: BoxFit.contain),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: EdgeInsets.only(left: 2, bottom: 5),
            child: Text('Chatra AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.teal))),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: isDark ? C.darkSurface : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(6), topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20),
              ),
              border: Border.all(color: C.teal.withOpacity(isDark ? 0.12 : 0.08)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.04), blurRadius: 10)],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => _Dot(delay: i * 180))),
          ),
        ]),
      ]),
    );
  }

  Widget _buildInput(Color surface, L10n l) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasText = _ctrl.text.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 90),
      decoration: BoxDecoration(
        color: surface,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.06), blurRadius: 14, offset: Offset(0, -2))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Container(
          constraints: BoxConstraints(minHeight: 46),
          decoration: BoxDecoration(
            color: adaptiveSurface2(context),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: hasText ? C.teal.withOpacity(0.3) : Colors.transparent, width: 1.5),
          ),
          child: TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              hintText: l.t('send_msg'),
              hintStyle: TextStyle(color: C.text4, fontSize: 15),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            ),
            onSubmitted: (_) => _send(),
            maxLines: 4,
            minLines: 1,
            onChanged: (_) => setState(() {}),
          ),
        )),
        SizedBox(width: 10),
        AnimatedContainer(
          duration: Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          width: 48, height: 48,
          decoration: BoxDecoration(
            gradient: !_loading ? LinearGradient(
              colors: hasText
                  ? [C.teal, C.tealDk]
                  : [C.teal.withOpacity(0.55), C.tealDk.withOpacity(0.45)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ) : null,
            color: _loading ? adaptiveSurface2(context) : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: hasText && !_loading ? [BoxShadow(color: C.teal.withOpacity(0.38), blurRadius: 14, offset: Offset(0, 4))] : null,
          ),
          child: GestureDetector(
            onTap: _send,
            child: _loading
              ? Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: C.teal)))
              : Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
          ),
        ),
      ]),
    );
  }
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});
  @override State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: 500));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _c.repeat(reverse: true);
    });
    _anim = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  }

  @override void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      width: 7, height: 7,
      margin: EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: C.teal.withOpacity(0.3 + _anim.value * 0.7),
        shape: BoxShape.circle,
      ),
      transform: Matrix4.translationValues(0, -4 * _anim.value, 0),
    ),
  );
}
