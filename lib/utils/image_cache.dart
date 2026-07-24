import 'dart:convert';
import 'dart:typed_data';
import 'dart:collection';

// Декодированные base64-обложки кэшируем, чтобы не гонять base64Decode на
// каждый build (это происходит для каждой карточки класса при скролле).
// Кэш ограничен: раньше это была бесконечно растущая Map, и десятки обложек
// по сотне КБ держали в памяти много мегабайт (риск OOM/лагов при GC).
const int _kMaxEntries = 40;
final LinkedHashMap<String, Uint8List> _decodedBase64Cache =
    LinkedHashMap<String, Uint8List>();

/// Обложка для списков/сеток/карточек — миниатюра (≤480px, поле
/// cover_thumbnail с бэкенда) вместо полноразмерной cover_image, чтобы не
/// гонять большие файлы при скролле каталога классов. Полноразмерный
/// cover_image остаётся только на странице самого класса (см. класс-детейл
/// экран и class_cover_sliver.dart — их не трогать).
String? cardCoverUrl(Map<String, dynamic> cls) =>
    (cls['cover_thumbnail'] as String?) ?? (cls['cover_image'] as String?);

Uint8List? decodeBase64Image(String dataUrl) {
  final cached = _decodedBase64Cache.remove(dataUrl);
  if (cached != null) {
    // Перекладываем в конец — простая LRU-эвикция.
    _decodedBase64Cache[dataUrl] = cached;
    return cached;
  }
  try {
    final bytes = base64Decode(dataUrl.split(',').last);
    _decodedBase64Cache[dataUrl] = bytes;
    if (_decodedBase64Cache.length > _kMaxEntries) {
      _decodedBase64Cache.remove(_decodedBase64Cache.keys.first);
    }
    return bytes;
  } catch (_) {
    return null;
  }
}
