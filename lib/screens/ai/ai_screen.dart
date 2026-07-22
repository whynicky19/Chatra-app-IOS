import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/ai_thread.dart';
import '../../providers/l10n_provider.dart';
import '../../providers/ai_chats_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';
import 'widgets/ai_conversation_view.dart';
import 'widgets/ai_history_drawer.dart';

/// Главный ИИ-ассистент. Переписка — всегда главный экран вкладки; история
/// чатов не отдельная страница, а drawer, открывающийся поверх неё (свайп
/// с левого края или иконка в шапке).
class AiScreen extends StatefulWidget {
  const AiScreen({super.key});
  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int? _activeThreadId;
  String? _activeTitle;
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
        _activeTitle = threads.first.title;
      });
    } else {
      setState(() => _picked = true);
    }
  }

  Future<void> _createChat() async {
    final l = context.read<L10n>();
    try {
      final t = await context.read<AiChatsProvider>().createThread();
      HapticFeedback.lightImpact();
      if (!mounted) return;
      setState(() {
        _activeThreadId = t.id;
        _activeTitle = t.title;
      });
      _scaffoldKey.currentState?.closeDrawer();
    } catch (_) {
      if (mounted) showToast(context, l.t('connection_error'), error: true);
    }
  }

  void _selectThread(AiThread t) {
    setState(() {
      _activeThreadId = t.id;
      _activeTitle = t.title;
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final surface = Theme.of(context).colorScheme.surface;

    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: AiHistoryDrawer(
        activeThreadId: _activeThreadId,
        onSelect: _selectThread,
        onCreate: _createChat,
      ),
      body: Column(children: [
        _buildHeader(surface, l),
        Expanded(
          child: AiConversationView(
            key: ValueKey('conv_${_activeThreadId ?? 'new'}'),
            threadId: _activeThreadId,
            onThreadCreated: (id) => setState(() => _activeThreadId = id),
            onTitleChanged: (title) => setState(() => _activeTitle = title),
          ),
        ),
      ]),
    );
  }

  Widget _buildHeader(Color surface, L10n l) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 8, 16, 10),
        decoration: BoxDecoration(
          color: surface,
          border: Border(bottom: BorderSide(color: adaptiveBorder(context).withValues(alpha: 0.5), width: 0.5)),
        ),
        child: Row(children: [
          IconButton(
            icon: Icon(CupertinoIcons.sidebar_left, color: adaptiveText1(context)),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          Expanded(
            child: Text(
              (_activeTitle ?? '').isEmpty ? 'Chatra AI' : _activeTitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4),
            ),
          ),
          GestureDetector(
            onTap: _createChat,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13)),
              child: Icon(CupertinoIcons.add, color: Theme.of(context).colorScheme.primary, size: 22),
            ),
          ),
        ]),
      ),
    );
  }
}
