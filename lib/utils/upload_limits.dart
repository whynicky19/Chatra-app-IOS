import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../providers/l10n_provider.dart';
import '../widgets/toast.dart';

/// Ограничения на прикрепляемые файлы.
const int kMaxUploadBytes = 25 * 1024 * 1024; // 25 МБ
const int kMaxFilesPerPost = 10;

/// Расширения, которые имеют смысл в учебной платформе И РАЗРЕШЕНЫ БЭКЕНДОМ
/// (routers/uploads.py ALLOWED_EXTENSIONS — там zip/rar/odt/ods/odp отклоняются
/// с 415: раньше клиент их разрешал, а сервер отвергал уже после долгой
/// загрузки). Исполняемые файлы и архивы сюда сознательно не входят.
const List<String> kAllowedExtensions = <String>[
  // Документы
  'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx',
  'txt', 'md', 'rtf', 'csv',
  // Изображения
  'png', 'jpg', 'jpeg', 'webp', 'heic', 'heif', 'gif',
];

/// Возвращает ключ локализации ошибки либо null, если всё в порядке.
String? validateUploads(List<PlatformFile> files) {
  if (files.length > kMaxFilesPerPost) return 'too_many_files';
  for (final f in files) {
    if (f.size > kMaxUploadBytes) return 'file_too_large';
    final ext = (f.extension ?? '').toLowerCase();
    if (!kAllowedExtensions.contains(ext)) return 'file_type_not_allowed';
  }
  return null;
}

/// Человекочитаемый размер для подписей в UI.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
}

/// Единая точка выбора файлов: пикер с фильтром по расширениям + валидация
/// размера и количества + понятное сообщение об ошибке.
Future<List<PlatformFile>?> pickUploadFiles(
  BuildContext context, {
  bool allowMultiple = true,
  int alreadyPicked = 0,
}) async {
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: allowMultiple,
    type: FileType.custom,
    allowedExtensions: kAllowedExtensions,
  );
  if (result == null || result.files.isEmpty) return null;
  if (!context.mounted) return null;

  final files = result.files.where((f) => f.path != null).toList();
  if (files.isEmpty) {
    showToast(context, context.read<L10n>().t('file_read_error'), error: true);
    return null;
  }

  if (alreadyPicked + files.length > kMaxFilesPerPost) {
    showToast(context, context.read<L10n>().t('too_many_files'), error: true);
    return null;
  }

  final err = validateUploads(files);
  if (err != null) {
    showToast(context, context.read<L10n>().t(err), error: true);
    return null;
  }
  return files;
}
