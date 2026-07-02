import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/avatar_models.dart';
import '../../../providers/l10n_provider.dart';
import '../../../services/api_service.dart';
import '../../../theme/app_theme.dart';
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

  Future<void> _deleteLecture(AvatarLecture lecture) async {
    final l = context.read<L10n>();
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: Text(l.t('lecture_delete_confirm')),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(c, false), child: Text(l.t('cancel'))),
          CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(c, true), child: Text(l.t('delete'))),
        ],
      ),
    );
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
            Text(l.t('avatar_lectures'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            ..._lectures.map((lec) => _LectureCard(
                  lecture: lec,
                  isTeacher: widget.isTeacher,
                  onTap: () => _openPlayer(lec),
                  onDelete: lec.canDelete ? () => _deleteLecture(lec) : null,
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
      widgets.add(GestureDetector(
        onTap: _openCreateAvatar,
        child: Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [const Color(0xFF006475), primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(18),
            boxShadow: primaryGlow(primary, opacity: 0.3),
          ),
          child: Row(children: [
            Container(width: 48, height: 48,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
              child: const Icon(CupertinoIcons.person_crop_circle_badge_plus, color: Colors.white, size: 24)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.t('create_avatar'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(l.t('no_avatar_lectures_teacher'), style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
            const Icon(CupertinoIcons.chevron_right, color: Colors.white70, size: 18),
          ]),
        ),
      ));
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
      widgets.add(SizedBox(width: double.infinity, child: ElevatedButton.icon(
        onPressed: _openCreateLecture,
        icon: const Icon(CupertinoIcons.add_circled, size: 18, color: Colors.white),
        label: Text(l.t('create_lecture')),
      )));
      if (avatar.voiceCloneWarning != null && avatar.voiceCloneWarning!.isNotEmpty) {
        widgets.add(const SizedBox(height: 12));
        widgets.add(_statusCard(
          icon: CupertinoIcons.exclamationmark_triangle_fill,
          color: C.amber,
          title: l.t('avatar_voice_warning_title'),
          sub: avatar.voiceCloneWarning,
        ));
      }
      widgets.add(const SizedBox(height: 16));
    }
    if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 4));
    return widgets;
  }

  Widget _statusCard({required IconData icon, required Color color, required String title, String? sub, Widget? action}) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          if (sub != null && sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
            child: Text(sub, style: const TextStyle(fontSize: 12, color: C.text4, height: 1.4))),
          if (action != null) Padding(padding: const EdgeInsets.only(top: 10), child: action),
        ])),
      ]),
    );
  }

  Widget _buildEmptyState(L10n l, Color primary) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 52),
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 80, height: 80,
          decoration: BoxDecoration(gradient: RadialGradient(colors: [primary.withValues(alpha: 0.16), primary.withValues(alpha: 0.04)]), shape: BoxShape.circle),
          child: Icon(CupertinoIcons.person_crop_rectangle, size: 36, color: primary)),
        const SizedBox(height: 18),
        Text(l.t('avatar_lectures'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: adaptiveText1(context))),
        const SizedBox(height: 6),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(
          widget.isTeacher ? l.t('no_avatar_lectures_teacher') : l.t('no_avatar_lectures_student'),
          style: const TextStyle(fontSize: 13, color: C.text4), textAlign: TextAlign.center)),
      ])),
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

    return Opacity(
      opacity: dimmed ? 0.65 : 1.0,
      child: GestureDetector(
        onTap: lecture.isReady ? onTap : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: cardShadow(isDark),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 44, height: 44,
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
                child: Icon(lecture.isReady ? CupertinoIcons.play_fill : statusIcon, color: statusColor, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(lecture.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Wrap(spacing: 10, runSpacing: 4, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(CupertinoIcons.clock, size: 12, color: C.text4), const SizedBox(width: 3),
                    Text('${lecture.durationMinutes} ${l.t('minutes_suffix')}', style: const TextStyle(fontSize: 12, color: C.text4)),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(CupertinoIcons.calendar, size: 12, color: C.text4), const SizedBox(width: 3),
                    Text(_fmtDate(lecture.createdAt), style: const TextStyle(fontSize: 12, color: C.text4)),
                  ]),
                ]),
              ])),
              if (isTeacher && onDelete != null) GestureDetector(
                onTap: onDelete,
                child: const Padding(padding: EdgeInsets.only(left: 6),
                  child: Icon(CupertinoIcons.trash, size: 18, color: C.text4)),
              ),
            ]),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(statusIcon, size: 12, color: statusColor),
                const SizedBox(width: 4),
                Text(statusText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
              ]),
            ),
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
