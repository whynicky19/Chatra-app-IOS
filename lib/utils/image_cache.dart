import 'dart:convert';
import 'dart:typed_data';

/// Caches decoded base64 image bytes keyed by the original data-URL string.
///
/// Without this, `Image.memory(base64Decode(...))` re-decodes the string on
/// every rebuild, allocating a fresh `Uint8List` each time. Because the byte
/// buffer identity changes, `Image.memory` treats it as a new image and
/// flickers on any `setState` (tab switch, load completion, reorder drag…).
/// Reusing the same `Uint8List` instance keeps the image stable.
final Map<String, Uint8List> _decodedBase64Cache = {};

/// Decodes a `data:...;base64,XXXX` string into cached bytes.
/// Returns null if the string is not valid base64.
Uint8List? decodeBase64Image(String dataUrl) {
  final cached = _decodedBase64Cache[dataUrl];
  if (cached != null) return cached;
  try {
    final bytes = base64Decode(dataUrl.split(',').last);
    _decodedBase64Cache[dataUrl] = bytes;
    return bytes;
  } catch (_) {
    return null;
  }
}
