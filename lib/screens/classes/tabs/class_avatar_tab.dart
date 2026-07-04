import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/avatar_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/l10n_provider.dart';
import '../../../services/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/skeleton.dart';
import '../../../widgets/toast.dart';
import '../../avatars/create_avatar_sheet.dart';
import '../../avatars/create_lecture_sheet.dart';
import '../../avatars/lecture_player_screen.dart';

class ClassAvatarTab extends StatefulWidget {
  final int classId;
  final bool isTeacher;
  final bool isActive;
  final void Function(int count) onLecturesChanged;

  const ClassAvatarTab({
    super.key,
    required this.classId,
    required this.isTeacher,
    required this.isActive,
    required this.onLecturesChanged,
  });

  @override
  State<ClassAvatarTab> createState() => _ClassAvatarTabState();
}

class _ClassAvatarTabState extends State<ClassAvatarTab> {
  bool _dataLoadTriggered = false;
  bool _loading = true;
  TeacherAvatar? _avatar; // only meaningful for the teacher
  List<AvatarLecture> _lectures = [];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _triggerLoad();
  }

  @override
  void didUpdateWidget(ClassAvatarTab old) {
    super.didUpdateWidget(old);
    if (!old.isActive && widget.isActive && !_dataLoadTriggered) _triggerLoad();
    if (old.isActive != widget.isActive) _syncPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _triggerLoad() {
    _dataLoadTriggered = true;
    _loadAll();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final api = context.read<ApiService>();
    try {
      final results = await Future.wait([
        widget.isTeacher ? api.getMyAvatar() : Future<Map<String, dynamic>?>.value(null),
        api.getClassAvatarLectures(widget.classId),
      ]);
      if (!mounted) return;
      final avatarJson = results[0] as Map<String, dynamic>?;
      final lecturesJson = results[1] as List<dynamic>;
      setState(() {
        _avatar = avatarJson != null ? TeacherAvatar.fromJson(avatarJson, api) : null;
        _lectures = lecturesJson.map((j) => AvatarLecture.fromJson(j as Map<String, dynamic>, api)).toList();
        _loading = false;
      });
      widget.onLecturesChanged(_lectures.length);
      _syncPolling();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _reloadLecturesOnly() async {
    if (!mounted) return;
    final api = context.read<ApiService>();
    try {
      final lecturesJson = await api.getClassAvatarLectures(widget.classId);
      if (!mounted) return;
      setState(() {
        _lectures = lecturesJson.map((j) => AvatarLecture.fromJson(j as Map<String, dynamic>, api)).toList();
      });
      widget.onLecturesChanged(_lectures.length);
      _syncPolling();
    } catch (_) {}
  }

  void _syncPolling() {
    final needsPolling = widget.isActive && _lectures.any((l) => l.isGenerating);
    if (needsPolling && _pollTimer == null) {
      _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _reloadLecturesOnly());
    } else if (!needsPolling && _pollTimer != null) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<void> _openCreateAvatar() async {
    final ok = await showCreateAvatarSheet(context);
    if (ok == true && mounted) _loadAll();
  }

  Future<void> _openCreateLecture() async {
    final ok = await showCreateLectureSheet(context, classId: widget.classId);
    if (ok == true && mounted) _loadAll();
  }

  // Удалять может владелец лекции или админ (это же правило на бэке).
  bool _canDeleteLecture(AvatarLecture lec) {
    final auth = context.read<AuthProvider>();
    return auth.isAdmin || (widget.isTeacher && lec.createdBy == auth.userId);
  }

  Future<void> _deleteLecture(AvatarLecture lecture) async {
    final l = context.read<L10n>();
    final ok = await showConfirmDialog(context,
      title: l.t('lecture_delete_confirm'),
      message: '«${lecture.title}»',
      icon: CupertinoIcons.trash,
      danger: true,
      confirmText: l.t('delete'),
      cancelText: l.t('cancel'));
    if (ok != true || !mounted) return;
    try {
      await context.read<ApiService>().deleteAvatarLecture(lecture.id);
      if (!mounted) return;
      showToast(context, l.t('class_deleted'));
      _reloadLecturesOnly();
    } catch (_) {
      if (mounted) showToast(context, l.t('error'), error: true);
    }
  }

  void _openPlayer(AvatarLecture lecture) {
    if (!lecture.isReady) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => LecturePlayerScreen(lectureId: lecture.id)));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;

    if (_loading) {
      return ListView(padding: const EdgeInsets.all(16), children: const [
        SkeletonBox(width: double.infinity, height: 100, borderRadius: 16),
        SizedBox(height: 12),
        SkeletonBox(width: double.infinity, height: 100, borderRadius: 16),
        SizedBox(height: 12),
        SkeletonBox(width: double.infinity, height: 100, borderRadius: 16),
      ]);
    }

    return RefreshIndicator(
      color: primary,
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (widget.isTeacher) ..._buildTeacherAvatarSection(l, primary),
          if (_lectures.isNotEmpty) ...[
            Row(children: [
              Container(width: 3, height: 18, decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 9),
              Text(l.t('avatar_lectures'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(8)),
                child: Text('${_lectures.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.text4)),
              ),
            ]),
            const SizedBox(height: 14),
            ..._lectures.map((lec) => _LectureCard(
                  lecture: lec,
                  isTeacher: widget.isTeacher,
                  onTap: () => _openPlayer(lec),
                  onDelete: _canDeleteLecture(lec) ? () => _deleteLecture(lec) : null,
                )),
          ] else
            _buildEmptyState(l, primary),
        ],
      ),
    );
  }

  List<Widget> _buildTeacherAvatarSection(L10n l, Color primary) {
    final avatar = _avatar;
    final widgets = <Widget>[];

    if (avatar == null) {
      widgets.add(_CreateAvatarBanner(onTap: _openCreateAvatar));
    } else if (avatar.isPending) {
      widgets.add(_statusCard(
        icon: CupertinoIcons.clock_fill,
        color: C.amber,
        title: l.t('avatar_pending_title'),
        sub: l.t('avatar_pending_sub'),
      ));
    } else if (avatar.isRejected) {
      widgets.add(_statusCard(
        icon: CupertinoIcons.xmark_circle_fill,
        color: C.red,
        title: l.t('avatar_rejected_title'),
        sub: avatar.rejectionReason,
        action: OutlinedButton(onPressed: _openCreateAvatar, child: Text(l.t('avatar_create_again'))),
      ));
    } else if (avatar.isApproved) {
      widgets.add(_ApprovedAvatarCard(avatar: avatar, primary: primary, onCreateLecture: _openCreateLecture));
      if (avatar.voiceCloneWarning != null && avatar.voiceCloneWarning!.isNotEmpty) {
        widgets.add(const SizedBox(height: 12));
        widgets.add(_statusCard(
          icon: CupertinoIcons.exclamationmark_triangle_fill,
          color: C.amber,
          title: l.t('avatar_voice_warning_title'),
          sub: avatar.voiceCloneWarning,
        ));
      }
      widgets.add(const SizedBox(height: 8));
    }
    if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 8));
    return widgets;
  }

  Widget _statusCard({required IconData icon, required Color color, required String title, String? sub, Widget? action}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: cardShadow(isDark),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 44, height: 44,
          decoration: BoxDecoration(gradient: RadialGradient(colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.1)]), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 21)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: color, height: 1.3)),
          if (sub != null && sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5),
            child: Text(sub, style: const TextStyle(fontSize: 12.5, color: C.text4, height: 1.45))),
          if (action != null) Padding(padding: const EdgeInsets.only(top: 12), child: action),
        ])),
      ]),
    );
  }

  Widget _buildEmptyState(L10n l, Color primary) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 84, height: 84,
          decoration: BoxDecoration(gradient: RadialGradient(colors: [primary.withValues(alpha: 0.18), primary.withValues(alpha: 0.03)]), shape: BoxShape.circle),
          child: Icon(CupertinoIcons.person_crop_rectangle, size: 38, color: primary)),
        const SizedBox(height: 18),
        Text(l.t('avatar_lectures'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: adaptiveText1(context))),
        const SizedBox(height: 6),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 28), child: Text(
          widget.isTeacher ? l.t('no_avatar_lectures_teacher') : l.t('no_avatar_lectures_student'),
          style: const TextStyle(fontSize: 13, color: C.text4, height: 1.5), textAlign: TextAlign.center)),
      ])),
    );
  }
}

/// Teacher-only banner shown when no avatar has been created yet.
class _CreateAvatarBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _CreateAvatarBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [const Color(0xFF006475), primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: primaryGlow(primary, opacity: 0.32),
        ),
        child: Stack(children: [
          Positioned(top: -18, right: -18, child: Icon(CupertinoIcons.sparkles, size: 90, color: Colors.white.withValues(alpha: 0.08))),
          Row(children: [
            Container(width: 52, height: 52,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(16)),
              child: const Icon(CupertinoIcons.person_crop_circle_badge_plus, color: Colors.white, size: 26)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.t('create_avatar'), style: const TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(l.t('no_avatar_lectures_teacher'), style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
            const SizedBox(width: 6),
            Container(width: 30, height: 30,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: const Icon(CupertinoIcons.chevron_right, color: Colors.white, size: 15)),
          ]),
        ]),
      ),
    );
  }
}

/// Compact "avatar profile" card for teachers whose avatar was approved:
/// photo, display name and an "active" pill, plus the primary CTA to create
/// a new lecture. Gives the tab a face instead of a bare button.
class _ApprovedAvatarCard extends StatelessWidget {
  final TeacherAvatar avatar;
  final Color primary;
  final VoidCallback onCreateLecture;
  const _ApprovedAvatarCard({required this.avatar, required this.primary, required this.onCreateLecture});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = avatar.displayName?.isNotEmpty == true ? avatar.displayName! : l.t('avatar');

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: cardShadow(isDark),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [const Color(0xFF006475), primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: primaryGlow(primary, opacity: 0.28),
            ),
            padding: const EdgeInsets.all(2),
            child: ClipOval(
              child: avatar.photoUrl != null
                  ? CachedNetworkImage(imageUrl: avatar.photoUrl!, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(CupertinoIcons.person_fill, color: Colors.white))
                  : Container(color: Colors.white.withValues(alpha: 0.15), child: const Icon(CupertinoIcons.person_fill, color: Colors.white)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: C.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: C.green, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(l.t('ready'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.green)),
              ]),
            ),
          ])),
        ]),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: onCreateLecture,
          icon: const Icon(CupertinoIcons.add_circled, size: 18, color: Colors.white),
          label: Text(l.t('create_lecture')),
        )),
      ]),
    );
  }
}

class _LectureCard extends StatelessWidget {
  final AvatarLecture lecture;
  final bool isTeacher;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _LectureCard({required this.lecture, required this.isTeacher, required this.onTap, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final dimmed = !lecture.isReady;

    final (statusColor, statusText, statusIcon) = switch (lecture.status) {
      'ready' => (C.green, l.t('ready'), CupertinoIcons.play_circle_fill),
      'pending_approval' => (C.amber, l.t('pending_approval'), CupertinoIcons.clock_fill),
      'approved' || 'generating' => (primary, l.t('generating'), CupertinoIcons.hourglass),
      'rejected' => (C.red, l.t('rejected'), CupertinoIcons.xmark_circle_fill),
      'failed' => (C.red, l.t('failed'), CupertinoIcons.exclamationmark_triangle_fill),
      _ => (C.text4, lecture.status, CupertinoIcons.question_circle),
    };

    return GestureDetector(
      onTap: lecture.isReady ? onTap : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: dimmed ? softShadow(isDark) : cardShadow(isDark),
          border: lecture.isReady ? Border.all(color: statusColor.withValues(alpha: 0.18)) : null,
        ),
        child: Opacity(
          opacity: dimmed ? 0.62 : 1.0,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 46, height: 46,
                decoration: BoxDecoration(
                  gradient: lecture.isReady
                      ? LinearGradient(colors: [statusColor, statusColor.withValues(alpha: 0.75)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                      : null,
                  color: lecture.isReady ? null : statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: lecture.isReady ? [BoxShadow(color: statusColor.withValues(alpha: 0.32), blurRadius: 10, offset: const Offset(0, 3))] : null,
                ),
                child: Icon(lecture.isReady ? CupertinoIcons.play_fill : statusIcon, color: lecture.isReady ? Colors.white : statusColor, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(lecture.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.25), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 7),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(CupertinoIcons.clock, size: 12, color: C.text4), const SizedBox(width: 4),
                    Text('${lecture.durationMinutes} ${l.t('minutes_suffix')}', style: const TextStyle(fontSize: 12, color: C.text4)),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(CupertinoIcons.calendar, size: 12, color: C.text4), const SizedBox(width: 4),
                    Text(_fmtDate(lecture.createdAt), style: const TextStyle(fontSize: 12, color: C.text4)),
                  ]),
                ]),
              ])),
              if (isTeacher && onDelete != null)
                GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(color: C.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(CupertinoIcons.trash, size: 15, color: C.red),
                  ),
                )
              else if (lecture.isReady)
                Icon(CupertinoIcons.chevron_right, size: 16, color: C.text4.withValues(alpha: 0.6)),
            ]),
            // Ready cards already read as playable (play tile + chevron) — a
            // status chip would just repeat that. Non-ready states keep the
            // chip, and generation shows a live progress strip so the teacher
            // can see the pipeline is actually working.
            if (!lecture.isReady) ...[
              const SizedBox(height: 11),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(statusText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                  ]),
                ),
                if (lecture.isGenerating) ...[
                  const SizedBox(width: 10),
                  Expanded(child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: statusColor,
                      backgroundColor: statusColor.withValues(alpha: 0.15),
                    ),
                  )),
                ],
              ]),
            ],
            if (lecture.isRejected && lecture.rejectionReason != null && lecture.rejectionReason!.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 8),
                child: Text(lecture.rejectionReason!, style: const TextStyle(fontSize: 12, color: C.red, height: 1.4))),
            if (lecture.isFailed && lecture.errorMessage != null && lecture.errorMessage!.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 8),
                child: Text(lecture.errorMessage!, style: const TextStyle(fontSize: 12, color: C.red, height: 1.4))),
          ]),
        ),
      ),
    );
  }

  String _fmtDate(String? d) {
    if (d == null || d.isEmpty) return '';
    try {
      final dt = DateTime.parse(d);
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {
      return d;
    }
  }
}
