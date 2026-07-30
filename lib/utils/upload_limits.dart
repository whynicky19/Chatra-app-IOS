import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../providers/l10n_provider.dart';
import '../widgets/toast.dart';

/// Ограничения на прикрепляемые файлы.
///
/// Раньше их не было вообще: `FileType.any` + `allowMultiple: true` + отправка
/// через `Future.wait`. Студент выбирал видео с телефона на 2 ГБ, sendTimeout
/// в 2 минуты гарантированно истекал, а публикация падала с невнятным
/// «upload_failed». Несколько крупных файлов параллельно давали пиковое
/// потребление памяти кратно их размеру — реальный риск OOM на бюджетных
/// Android.
///
/// Проверка на клиенте — это UX, а не безопасность: те же лимиты обязаны
/// стоять на бэкенде.
const int kMaxUploadBytes = 25 * 1024 * 1024; // 25 МБ
const int kMaxFilesPerPost = 10;

/// Расширения, которые имеют смысл в учебной платформе. Исполняемые файлы и
/// архивы с кодом сюда сознательно не входят.
const List<String> kAllowedExtensions = <String>[
  // Документы
  'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx',
  'txt', 'md', 'rtf', 'csv', 'odt', 'ods', 'odp',
  // Изображения
  'png', 'jpg', 'jpeg', 'webp', 'heic', 'gif',
  // Архивы
  'zip',
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
///
/// Возвращает null, если пользователь отменил выбор или файлы не прошли
/// проверку (тост уже показан). Все экраны обязаны ходить через неё, иначе
/// лимиты снова разъедутся по кодовой базе.
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
