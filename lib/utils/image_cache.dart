import 'dart:convert';
import 'dart:typed_data';

final Map<String, Uint8List> _decodedBase64Cache = {};

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
