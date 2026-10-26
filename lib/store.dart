import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import 'audio_analysis_models.dart';

/// Un resultado guardado: los numeros del analisis + datos del archivo para
/// saber si cambio (tamano y fecha de modificacion).
class StoredResult {
  const StoredResult({
    required this.data,
    required this.size,
    required this.mtime,
  });
  final AudioAnalysisData data;
  final int size;
  final int mtime;
}

/// Guarda solo los NUMEROS de cada cancion (unos 2 KB por cancion) en un JSON.
class ResultsStore {
  static const _version = 1;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/results_v$_version.json');
  }

  static Future<Map<String, StoredResult>> load() async {
    final out = <String, StoredResult>{};
    try {
      final f = await _file();
      if (!await f.exists()) return out;
      final text = await f.readAsString();
      // Con miles de canciones el JSON pesa MB: se decodifica fuera del hilo
      // de la UI para que la app abra sin congelarse.
      final json = await Isolate.run(
        () => jsonDecode(text) as Map<String, dynamic>,
      );
      final items = json['items'] as Map<String, dynamic>? ?? {};
      for (final entry in items.entries) {
        try {
          final m = entry.value as Map<String, dynamic>;
          final dataJson = Map<String, dynamic>.from(m['data'] as Map);
          if (dataJson['cacheVersion'] != AudioAnalysisData.cacheVersion) {
            continue;
          }
          out[entry.key] = StoredResult(
            data: AudioAnalysisData.fromJson(dataJson),
            size: m['size'] as int,
            mtime: m['mtime'] as int,
          );
        } catch (_) {}
      }
    } catch (_) {}
    return out;
  }

  static Future<void> save(Map<String, StoredResult> items) async {
    try {
      final payload = <String, dynamic>{
        'v': _version,
        'items': {
          for (final e in items.entries)
            e.key: {
              'size': e.value.size,
              'mtime': e.value.mtime,
              'data': e.value.data.toJson(),
            },
        },
      };
      final text = await Isolate.run(() => jsonEncode(payload));
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(text);
      await tmp.rename(f.path);
    } catch (_) {}
  }

  static Future<int> sizeBytes() async {
    try {
      final f = await _file();
      return await f.exists() ? await f.length() : 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// Cache de espectrogramas con TOPE de espacio. Cuando se pasa del tope borra
/// los mas viejos (los que hace mas tiempo no abres).
class SpectrogramCache {
  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/spectrograms');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Hash FNV-1a de 64 bits (estable entre ejecuciones).
  static String keyFor(String path, int size, int mtime) {
    var h = 0xcbf29ce484222325;
    for (final b in utf8.encode('$path|$size|$mtime')) {
      h ^= b;
      h *= 0x100000001b3;
    }
    return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  static String _name(String key, int channel) =>
      channel < 0 ? '$key.png' : '${key}_ch$channel.png';

  static Future<ui.Image?> load(String key, int channel) async {
    try {
      final f = File('${(await _dir()).path}/${_name(key, channel)}');
      if (!await f.exists()) return null;
      final bytes = await f.readAsBytes();
      await f.setLastModified(DateTime.now());
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, completer.complete);
      return await completer.future;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(
    String key,
    int channel,
    ui.Image image,
    int budgetBytes,
  ) async {
    if (budgetBytes <= 0) return;
    try {
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return;
      final dir = await _dir();
      await File(
        '${dir.path}/${_name(key, channel)}',
      ).writeAsBytes(bd.buffer.asUint8List());
      await trim(budgetBytes);
    } catch (_) {}
  }

  static Future<void> trim(int maxBytes) async {
    try {
      final dir = await _dir();
      final files = <MapEntry<File, FileStat>>[];
      var total = 0;
      await for (final e in dir.list()) {
        if (e is File && e.path.endsWith('.png')) {
          final st = await e.stat();
          files.add(MapEntry(e, st));
          total += st.size;
        }
      }
      if (total <= maxBytes) return;
      files.sort((a, b) => a.value.modified.compareTo(b.value.modified));
      final target = (maxBytes * 0.75).round();
      for (final f in files) {
        if (total <= target) break;
        try {
          await f.key.delete();
          total -= f.value.size;
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Future<int> sizeBytes() async {
    var total = 0;
    try {
      final dir = await _dir();
      await for (final e in dir.list()) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }

  static Future<void> clear() async {
    try {
      final dir = await _dir();
      await for (final e in dir.list()) {
        if (e is File) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
