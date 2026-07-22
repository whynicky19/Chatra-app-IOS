import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/ai_thread.dart';
import '../../providers/ai_chats_provider.dart';
import '../../theme/app_theme.dart';
import 'widgets/ai_conversation_view.dart';
import 'widgets/ai_history_drawer.dart';

/// Главный ИИ-ассистент. Переписка — всегда главный экран вкладки; история
/// чатов не отдельная страница, а drawer, открывающийся поверх неё (свайп
/// с левого края или круглая кнопка сверху).
class AiScreen extends StatefulWidget {
  const AiScreen({super.key});
  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int? _activeThreadId;
  bool _picked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<AiChatsProvider>().load();
      _pickInitialThread();
    });
  }

  void _pickInitialThread() {
    if (_picked || !mounted) return;
    final threads = context.read<AiChatsProvider>().threads;
    if (threads.isNotEmpty) {
      setState(() {
        _picked = true;
        _activeThreadId = threads.first.id;
      });
    } else {
      setState(() => _picked = true);
    }
  }

  /// «Новый чат» просто сбрасывает экран в пустое состояние — тред на бэке
  /// создаётся лениво при первой отправке (см. AiConversationView), иначе
  /// в истории копились бы пустые чаты, если пользователь ничего не написал.
  void _createChat() {
    setState(() => _activeThreadId = null);
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _selectThread(AiThread t) {
    setState(() => _activeThreadId = t.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top + 56;

    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: AiHistoryDrawer(
        activeThreadId: _activeThreadId,
        onSelect: _selectThread,
        onCreate: _createChat,
      ),
      body: Stack(children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(top: topInset),
            child: AiConversationView(
              key: ValueKey('conv_${_activeThreadId ?? 'new'}'),
              threadId: _activeThreadId,
              onThreadCreated: (id) => setState(() => _activeThreadId = id),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          child: _HistoryButton(onTap: () => _scaffoldKey.currentState?.openDrawer()),
        ),
      ]),
    );
  }
}

class _HistoryButton extends StatelessWidget {
  final VoidCallback onTap;
  const _HistoryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? C.darkSurface2.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.9),
          boxShadow: cardShadow(isDark),
        ),
        child: Icon(CupertinoIcons.sidebar_left, size: 20, color: adaptiveText1(context)),
      ),
    );
  }
}
