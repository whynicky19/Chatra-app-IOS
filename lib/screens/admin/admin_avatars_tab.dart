import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../../models/avatar_models.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../utils/dates.dart';
import '../../utils/file_opener.dart';
import '../../widgets/toast.dart';

class AdminAvatarsTab extends StatefulWidget {
  final bool isActive;
  final void Function(int pendingCount) onPendingCountChanged;

  const AdminAvatarsTab({super.key, required this.isActive, required this.onPendingCountChanged});

  @override
  State<AdminAvatarsTab> createState() => _AdminAvatarsTabState();
}

class _AdminAvatarsTabState extends State<AdminAvatarsTab> with SingleTickerProviderStateMixin {
  late final TabController _subTabCtrl;
  bool _triggered = false;

  bool _loadingAvatars = true;
  List<TeacherAvatar> _avatars = [];
  String _avatarFilter = 'all';

  bool _loadingLectures = true;
  List<AvatarLecture> _lectures = [];

  @override
  void initState() {
    super.initState();
    _subTabCtrl = TabController(length: 2, vsync: this);
    if (widget.isActive) _load();
  }

  @override
  void didUpdateWidget(AdminAvatarsTab old) {
    super.didUpdateWidget(old);
    if (!old.isActive && widget.isActive && !_triggered) _load();
  }

  @override
  void dispose() {
    _subTabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _triggered = true;
    await Future.wait([_loadAvatars(), _loadLectures()]);
  }

  Future<void> _loadAvatars() async {
    if (!mounted) return;
    setState(() => _loadingAvatars = true);
    final api = context.read<ApiService>();
    try {
      final json = await api.adminAvatars(status: _avatarFilter == 'all' ? null : _avatarFilter);
      if (!mounted) return;
      setState(() {
        _avatars = json.map((j) => TeacherAvatar.fromJson(j as Map<String, dynamic>, api)).toList();
        _loadingAvatars = false;
      });
      _notifyPendingCount();
    } catch (_) {
      if (mounted) setState(() => _loadingAvatars = false);
    }
  }

  Future<void> _loadLectures() async {
    if (!mounted) return;
    setState(() => _loadingLectures = true);
    final api = context.read<ApiService>();
    try {
      final json = await api.adminAvatarLectures();
      if (!mounted) return;
      setState(() {
        _lectures = json.map((j) => AvatarLecture.fromJson(j as Map<String, dynamic>, api)).toList();
        _loadingLectures = false;
      });
      _notifyPendingCount();
    } catch (_) {
      if (mounted) setState(() => _loadingLectures = false);
    }
  }

  void _notifyPendingCount() {
    final pendingAvatars = _avatarFilter == 'all' ? _avatars.where((a) => a.isPending).length : (_avatarFilter == 'pending' ? _avatars.length : 0);
    final pendingLectures = _lectures.where((l) => l.isPendingApproval).length;
    widget.onPendingCountChanged(pendingAvatars + pendingLectures);
  }

  Future<void> _reviewAvatar(TeacherAvatar avatar, {required bool approve, String? reason}) async {
    final l = context.read<L10n>();
    try {
      await context.read<ApiService>().adminReviewAvatar(avatar.id, approve: approve, rejectionReason: reason);
      if (!mounted) return;
      showToast(context, l.t('save_ok'));
      _loadAvatars();
    } catch (_) {
      if (mounted) showToast(context, l.t('error'), error: true);
    }
  }

  Future<void> _deleteAvatar(TeacherAvatar avatar) async {
    final l = context.read<L10n>();
    final ok = await _confirmDelete(l);
    if (ok != true || !mounted) return;
    try {
      await context.read<ApiService>().adminDeleteAvatar(avatar.id);
      if (!mounted) return;
      showToast(context, l.t('class_deleted'));
      _loadAvatars();
    } catch (_) {
      if (mounted) showToast(context, l.t('error'), error: true);
    }
  }

  Future<void> _reviewLecture(AvatarLecture lecture, {required bool approve, String? reason}) async {
    final l = context.read<L10n>();
    try {
      await context.read<ApiService>().adminReviewAvatarLecture(lecture.id, approve: approve, rejectionReason: reason);
      if (!mounted) return;
      showToast(context, l.t('save_ok'));
      _loadLectures();
    } catch (_) {
      if (mounted) showToast(context, l.t('error'), error: true);
    }
  }

  Future<bool?> _confirmDelete(L10n l) {
    return showConfirmDialog(context,
      title: l.t('admin_delete_confirm_title'),
      icon: CupertinoIcons.trash,
      danger: true,
      confirmText: l.t('delete'),
      cancelText: l.t('cancel'));
  }

  Future<String?> _promptRejectionReason(L10n l) {
    return showInputDialog(context,
      title: l.t('reject_reason_title'),
      hint: l.t('reject_reason_hint'),
      icon: CupertinoIcons.xmark_circle,
      danger: true,
      maxLines: 3,
      confirmText: l.t('reject'),
      cancelText: l.t('cancel'));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(children: [
      Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadii.tile), boxShadow: softShadow(isDark)),
        child: TabBar(
          controller: _subTabCtrl,
          labelColor: primary,
          unselectedLabelColor: C.text4,
          indicatorColor: primary,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
          tabs: [Tab(text: l.t('admin_avatar_requests')), Tab(text: l.t('admin_avatar_lectures'))],
        ),
      ),
      Expanded(child: TabBarView(controller: _subTabCtrl, children: [
        _buildAvatarsSubTab(l, primary, isDark),
        _buildLecturesSubTab(l, primary, isDark),
      ])),
    ]);
  }

  Widget _buildAvatarsSubTab(L10n l, Color primary, bool isDark) {
    if (_loadingAvatars) return Center(child: CircularProgressIndicator(color: primary, strokeWidth: 2.5));
    final headers = <Widget>[
      Row(children: [
        for (final f in const ['all', 'pending', 'approved', 'rejected']) ...[
          _filterChip(f == 'all' ? l.t('filter_all') : (f == 'pending' ? l.t('pending_approval') : (f == 'approved' ? l.t('ready') : l.t('rejected'))),
            selected: _avatarFilter == f, onTap: () { setState(() => _avatarFilter = f); _loadAvatars(); }, primary: primary),
          const SizedBox(width: 8),
        ],
      ]),
      const SizedBox(height: 12),
      if (_avatars.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: Center(child: Text(l.t('no_ai_data'), style: const TextStyle(color: C.text4)))),
    ];
    return RefreshIndicator(
      color: primary,
      onRefresh: _loadAvatars,
      // Ленивый список: заявки на аватары могут быть длинным org-wide списком.
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: headers.length + _avatars.length,
        itemBuilder: (ctx, index) {
          if (index < headers.length) return headers[index];
          final a = _avatars[index - headers.length];
          return _AvatarRequestCard(
            avatar: a,
            isDark: isDark,
            onApprove: () => _reviewAvatar(a, approve: true),
            onReject: () async { final reason = await _promptRejectionReason(l); if (reason != null) _reviewAvatar(a, approve: false, reason: reason); },
            onDelete: () => _deleteAvatar(a),
          );
        },
      ),
    );
  }

  Widget _buildLecturesSubTab(L10n l, Color primary, bool isDark) {
    if (_loadingLectures) return Center(child: CircularProgressIndicator(color: primary, strokeWidth: 2.5));
    return RefreshIndicator(
      color: primary,
      onRefresh: _loadLectures,
      child: _lectures.isEmpty
          ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
              Padding(padding: const EdgeInsets.symmetric(vertical: 40), child: Center(child: Text(l.t('no_ai_data'), style: const TextStyle(color: C.text4)))),
            ])
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _lectures.length,
              itemBuilder: (ctx, index) {
                final lec = _lectures[index];
                return _AdminLectureCard(
                  lecture: lec,
                  isDark: isDark,
                  onApprove: () => _reviewLecture(lec, approve: true),
                  onReject: () async { final reason = await _promptRejectionReason(l); if (reason != null) _reviewLecture(lec, approve: false, reason: reason); },
                );
              },
            ),
    );
  }

  Widget _filterChip(String label, {required bool selected, required VoidCallback onTap, required Color primary}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: selected ? primary : adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.chip)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : C.text3)),
      ),
    );
  }
}

class _AvatarRequestCard extends StatelessWidget {
  final TeacherAvatar avatar;
  final bool isDark;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDelete;

  const _AvatarRequestCard({required this.avatar, required this.isDark, required this.onApprove, required this.onReject, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final statusColor = avatar.isPending ? C.amber : (avatar.isApproved ? C.green : C.red);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), boxShadow: cardShadow(isDark)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(shape: BoxShape.circle, color: adaptiveSurface2(context)),
            clipBehavior: Clip.antiAlias,
            child: avatar.photoUrl != null
                ? Image.network(avatar.photoUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(CupertinoIcons.person_fill, color: C.text4))
                : const Icon(CupertinoIcons.person_fill, color: C.text4)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(avatar.displayName?.isNotEmpty == true ? avatar.displayName! : l.t('admin_no_name'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('${l.t('admin_teacher_label')} ${avatar.teacherId} · ${_fmtDate(avatar.createdAt)}', style: const TextStyle(fontSize: 11, color: C.text4)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(avatar.isPending ? l.t('pending_approval') : (avatar.isApproved ? l.t('ready') : l.t('rejected')),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: statusColor))),
        ]),
        if (avatar.voiceSampleUrl != null) ...[
          const SizedBox(height: 10),
          _MiniAudioPlayer(url: avatar.voiceSampleUrl!),
        ],
        if (avatar.isRejected && avatar.rejectionReason != null && avatar.rejectionReason!.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(avatar.rejectionReason!, style: const TextStyle(fontSize: 12, color: C.red, height: 1.4))),
        if (avatar.isApproved && avatar.voiceCloneWarning != null && avatar.voiceCloneWarning!.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8),
            child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: C.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadii.chip)),
              child: Row(children: [
                const Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 14, color: C.amber),
                const SizedBox(width: 6),
                Expanded(child: Text(avatar.voiceCloneWarning!, style: const TextStyle(fontSize: 11, color: C.amber))),
              ]))),
        const SizedBox(height: 10),
        Row(children: [
          if (avatar.isPending) ...[
            Expanded(child: OutlinedButton(onPressed: onApprove,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10), side: const BorderSide(color: C.green)),
              child: Text(l.t('approve'), style: const TextStyle(color: C.green, fontSize: 12)))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: onReject,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10), side: const BorderSide(color: C.red)),
              child: Text(l.t('reject'), style: const TextStyle(color: C.red, fontSize: 12)))),
            const SizedBox(width: 8),
          ],
          GestureDetector(onTap: onDelete, child: Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadii.chip)),
            child: const Icon(CupertinoIcons.trash, size: 16, color: C.red))),
        ]),
      ]),
    );
  }

  String _fmtDate(String d) => fmtDateTimeLocal(d);
}

class _AdminLectureCard extends StatelessWidget {
  final AvatarLecture lecture;
  final bool isDark;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _AdminLectureCard({required this.lecture, required this.isDark, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    final (statusColor, statusText) = switch (lecture.status) {
      'ready' => (C.green, l.t('ready')),
      'pending_approval' => (C.amber, l.t('pending_approval')),
      'approved' || 'generating' => (primary, l.t('generating')),
      'rejected' => (C.red, l.t('rejected')),
      'failed' => (C.red, l.t('failed')),
      _ => (C.text4, lecture.status),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), boxShadow: cardShadow(isDark)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(lecture.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis)),
          Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: statusColor))),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 6, children: [
          _metaItem(CupertinoIcons.tag,
            lecture.className?.isNotEmpty == true ? lecture.className! : '${l.t('class_label')} ${lecture.classId}'),
          _metaItem(CupertinoIcons.clock, '${lecture.durationMinutes} ${l.t('minutes_suffix')}'),
          _metaItem(CupertinoIcons.text_bubble, lecture.style),
          _metaItem(CupertinoIcons.calendar, _fmtDate(lecture.createdAt)),
        ]),
        const SizedBox(height: 6),
        Text('${l.t('estimated_cost')}: ~\$${lecture.estimatedCostUsd.toStringAsFixed(2)} (${lecture.estimatedChars} ${l.t('characters_label')})',
          style: const TextStyle(fontSize: 12, color: C.text4)),
        if (lecture.sourceFileUrl != null) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => openRemoteFile(context, context.read<ApiService>(),
                lecture.sourceFileUrl!, lecture.sourceFilename ?? 'presentation'),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primary.withValues(alpha: 0.18)),
              ),
              child: Row(children: [
                Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadii.chip)),
                  child: Icon(
                    (lecture.sourceFilename ?? '').toLowerCase().endsWith('.pdf')
                        ? CupertinoIcons.doc_text_fill : CupertinoIcons.film_fill,
                    size: 17, color: primary)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(lecture.sourceFilename ?? l.t('open_presentation'),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(l.t('open_presentation'), style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w600)),
                ])),
                Icon(CupertinoIcons.arrow_up_right_square, size: 16, color: primary),
              ]),
            ),
          ),
        ],
        if (lecture.isRejected && lecture.rejectionReason != null && lecture.rejectionReason!.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(lecture.rejectionReason!, style: const TextStyle(fontSize: 12, color: C.red, height: 1.4))),
        if (lecture.isFailed && lecture.errorMessage != null && lecture.errorMessage!.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(lecture.errorMessage!, style: const TextStyle(fontSize: 12, color: C.red, height: 1.4))),
        if (lecture.isPendingApproval) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: onApprove,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10), side: const BorderSide(color: C.green)),
              child: Text(l.t('approve'), style: const TextStyle(color: C.green, fontSize: 12)))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: onReject,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10), side: const BorderSide(color: C.red)),
              child: Text(l.t('reject'), style: const TextStyle(color: C.red, fontSize: 12)))),
          ]),
        ],
      ]),
    );
  }

  Widget _metaItem(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: C.text4), const SizedBox(width: 3),
        Text(text, style: const TextStyle(fontSize: 11, color: C.text4)),
      ]);

  String _fmtDate(String d) => fmtDateTimeLocal(d);
}

class _MiniAudioPlayer extends StatefulWidget {
  final String url;
  const _MiniAudioPlayer({required this.url});
  @override
  State<_MiniAudioPlayer> createState() => _MiniAudioPlayerState();
}

class _MiniAudioPlayerState extends State<_MiniAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _loaded = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player.pause();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }
    try {
      if (!_loaded) {
        await _player.setUrl(widget.url);
        _loaded = true;
        _player.playerStateStream.listen((s) {
          if (s.processingState == ProcessingState.completed && mounted) setState(() => _isPlaying = false);
        });
      }
      if (!mounted) return;
      setState(() => _isPlaying = true);
      await _player.play();
    } catch (_) {
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.chip)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, size: 14, color: primary),
          const SizedBox(width: 6),
          Text(_isPlaying ? l.t('pause') : l.t('play'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primary)),
        ]),
      ),
    );
  }
}
