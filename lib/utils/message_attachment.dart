/// Разбор вложения в тексте сообщения.
///
/// Форматы, которые реально ходят по одной и той же переписке:
///   * сайт: `🖼️ [Фото](http://host/uploads/xxx.png?exp=..&sig=..) — ceo.png`
///   * приложение: голая ссылка `/uploads/xxx.png`
///
/// Раньше приложение вытаскивало ссылку регуляркой `https?://\S+?\.(png|...)`,
/// и из markdown-варианта в URL уезжала закрывающая скобка `)` — подпись
/// ломалась, картинка не грузилась и вместо фото показывался путь к файлу.
library;

class MessageAttachment {
  final String url;
  final String name;
  final bool isImage;
  /// Текст сообщения без служебной markdown-обвязки (подпись к вложению).
  final String caption;

  const MessageAttachment({
    required this.url,
    required this.name,
    required this.isImage,
    this.caption = '',
  });
}

const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'};

// [Фото](url) — url без пробелов и без закрывающей скобки.
final _mdLinkRe = RegExp(r'\[([^\]]*)\]\(([^()\s]+)\)');
// Голая ссылка на загрузку — абсолютная или относительная.
final _bareUploadRe =
    RegExp(r'^(?:https?://\S+?)?/?uploads/\S+$', caseSensitive: false);

/// Путь без query и fragment — по нему определяем расширение.
String _pathOf(String url) {
  var s = url;
  final hash = s.indexOf('#');
  if (hash >= 0) s = s.substring(0, hash);
  final q = s.indexOf('?');
  if (q >= 0) s = s.substring(0, q);
  return s;
}

bool isImageUrl(String url) {
  final path = _pathOf(url);
  final dot = path.lastIndexOf('.');
  if (dot < 0) return false;
  return _imageExts.contains(path.substring(dot + 1).toLowerCase());
}

/// Исходное имя файла: сайт кладёт его после `— `, приложение — во fragment
/// `#имя.png`; иначе берём последний сегмент пути.
String _nameFor(String url, String? explicit) {
  if (explicit != null && explicit.trim().isNotEmpty) return explicit.trim();
  final hash = url.indexOf('#');
  if (hash >= 0 && hash < url.length - 1) {
    return Uri.decodeComponent(url.substring(hash + 1));
  }
  final path = _pathOf(url);
  final seg = path.split('/').last;
  return seg.isEmpty ? url : seg;
}

/// Вложение из текста сообщения; null — обычный текст.
MessageAttachment? parseMessageAttachment(String content) {
  final text = content.trim();
  if (text.isEmpty) return null;

  final md = _mdLinkRe.firstMatch(text);
  if (md != null) {
    final url = md.group(2)!;
    // Подпись: всё, кроме самой ссылки, эмодзи-маркера и « — имя.png».
    var rest = text.replaceRange(md.start, md.end, '').trim();
    String? explicitName;
    final dash = rest.indexOf('—');
    if (dash >= 0) {
      explicitName = rest.substring(dash + 1).trim();
      rest = rest.substring(0, dash).trim();
    }
    // Одиночный эмодзи-маркер (🖼️/📎) подписью не считаем.
    if (rest.length <= 3) rest = '';
    return MessageAttachment(
      url: url,
      name: _nameFor(url, explicitName),
      isImage: isImageUrl(url),
      caption: rest,
    );
  }

  if (!text.contains(' ') && _bareUploadRe.hasMatch(text)) {
    return MessageAttachment(
      url: text,
      name: _nameFor(text, null),
      isImage: isImageUrl(text),
    );
  }
  return null;
}

/// Короткая подпись вместо ссылки — для цитат и превью ответов.
/// Возвращает исходный текст, если вложения в нём нет.
String messagePreviewText(String content) {
  final att = parseMessageAttachment(content);
  if (att == null) return content;
  return '${att.isImage ? '📷' : '📎'} ${att.name}';
}
