import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'analyzer.dart';
import 'background.dart';
import 'audio_analysis_models.dart';
import 'store.dart';

const _audioExtensions = {
  '.flac', '.mp3', '.m4a', '.aac', '.opus', '.ogg', '.wav', '.wma', '.wv',
  '.ape', '.tta', '.aif', '.aiff', '.ac3', '.eac3', '.mka',
};

bool isAudioPath(String path) {
  final lower = path.toLowerCase();
  return _audioExtensions.any(lower.endsWith);
}

enum ItemState { waiting, running, done, error }

class Item {
  Item({
    required this.path,
    required this.size,
    required this.mtime,
    this.temp = false,
  });

  final String path;
  final int size;
  final int mtime;

  /// Archivo suelto (copia temporal): no se guarda en la biblioteca.
  final bool temp;

  ItemState state = ItemState.waiting;
  AudioAnalysisData? data;
  String? error;

  // Se calculan una sola vez: antes se recreaban en cada comparacion del
  // ordenamiento, en cada reconstruccion de la lista.
  late final String name = path.split('/').last;
  late final String nameLower = name.toLowerCase();
  String get cacheKey => SpectrogramCache.keyFor(path, size, mtime);
}

enum SortKey { name, dr, lufs, cutoff }

enum LibFilter { all, suspicious, compressed }

const _losslessCodecs = {'flac', 'alac', 'wavpack', 'ape', 'tta'};

/// Marca canciones lossless cuyo espectro sugiere un origen con perdida.
String? suspicionOf(AudioAnalysisData d) {
  final codec = d.codec.toLowerCase();
  final lossless = _losslessCodecs.contains(codec) || codec.startsWith('pcm_');
  if (!lossless) return null;
  final cutoff = d.spectralCutoffHz;
  if (cutoff == null) return null;
  if (d.sampleRate > 48000 && cutoff < 23000) {
    return 'Posible upsample (corte en ${(cutoff / 1000).toStringAsFixed(1)} kHz)';
  }
  if (cutoff < 19000) {
    return 'Posible transcode de MP3/AAC (corte en ${(cutoff / 1000).toStringAsFixed(1)} kHz)';
  }
  return null;
}

bool isCompressed(AudioAnalysisData d) => d.dynamicRange < 8;

class LibrarySummary {
  const LibrarySummary({
    required this.analyzed,
    required this.avgDr,
    required this.avgLufs,
    required this.suspicious,
  });
  final int analyzed;
  final double? avgDr;
  final double? avgLufs;
  final int suspicious;
}

class LibraryController extends ChangeNotifier {
  /// [concurrency] devuelve cuantas canciones analizar a la vez (0 = auto).
  LibraryController({int Function()? concurrency})
    : _concurrency = concurrency ?? (() => 0);

  final int Function() _concurrency;
  final Analyzer analyzer = Analyzer();
  final Map<String, Item> _items = {};
  final List<Item> _queue = [];

  bool running = false;
  bool scanning = false;
  int runTotal = 0;
  int runDone = 0;
  String? currentName;
  bool _stop = false;
  int _unsaved = 0;

  int _active = 0;
  int _okCount = 0;
  int _errCount = 0;
  bool _finishing = false;
  final Stopwatch _runWatch = Stopwatch();
  Timer? _notifyTimer;
  DateTime _lastServiceUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _saveChain = Future.value();

  /// Canciones que se analizan a la vez. Cada una ya lanza 3 FFmpeg, asi que
  /// en auto se usa ~1 cancion por cada 4 nucleos (maximo 3).
  int get workerLimit {
    final v = _concurrency();
    if (v > 0) return v;
    return math.max(1, math.min(3, Platform.numberOfProcessors ~/ 4));
  }

  /// Segundos estimados que faltan (null hasta tener un minimo de muestras).
  int? get etaSeconds {
    if (!running || runDone < 3) return null;
    final perItem = _runWatch.elapsedMilliseconds / runDone;
    final left = math.max(0, runTotal - runDone);
    return (perItem * left / 1000).round();
  }

  /// Avisa a la UI como mucho 4 veces por segundo (con analisis en paralelo
  /// y miles de canciones, reconstruir la lista en cada cambio la satura).
  void _notifySoon() {
    if (_notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: 250), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  Future<void> init() async {
    final stored = await ResultsStore.load();
    for (final e in stored.entries) {
      _items[e.key] = Item(
        path: e.key,
        size: e.value.size,
        mtime: e.value.mtime,
      )
        ..data = e.value.data
        ..state = ItemState.done;
    }
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } catch (_) {}
    notifyListeners();
  }

  int get totalItems => _items.length;

  /// Canciones ya analizadas (para duplicados y comparar).
  List<Item> get analyzedItems => _items.values
      .where((i) => i.state == ItemState.done && i.data != null)
      .toList();

  /// Agrega archivos a la cola. Devuelve cuantos se van a analizar.
  Future<int> addPaths(Iterable<String> paths, {bool temp = false}) async {
    var added = 0;
    for (final p in paths) {
      if (!isAudioPath(p)) continue;
      try {
        final st = await File(p).stat();
        if (st.type != FileSystemEntityType.file) continue;
        final mtime = st.modified.millisecondsSinceEpoch;
        final existing = _items[p];
        if (existing != null) {
          if (existing.state == ItemState.waiting ||
              existing.state == ItemState.running) {
            continue;
          }
          if (existing.state == ItemState.done &&
              existing.size == st.size &&
              existing.mtime == mtime) {
            continue;
          }
        }
        final item = Item(path: p, size: st.size, mtime: mtime, temp: temp);
        _items[p] = item;
        _queue.add(item);
        added++;
      } catch (_) {}
    }
    notifyListeners();
    if (added > 0) unawaited(_runQueue());
    return added;
  }

  /// Busca audio dentro de una carpeta (con subcarpetas).
  Future<({int found, int added})> addFolder(String dir) async {
    scanning = true;
    notifyListeners();
    final found = <String>[];
    try {
      final stream = Directory(
        dir,
      ).list(recursive: true, followLinks: false).handleError((_) {});
      await for (final e in stream) {
        if (e is File && isAudioPath(e.path)) found.add(e.path);
      }
    } catch (_) {}
    scanning = false;
    final added = await addPaths(found);
    return (found: found.length, added: added);
  }

  Future<void> _runQueue() async {
    if (running) {
      _pump();
      return;
    }
    running = true;
    _stop = false;
    _okCount = 0;
    _errCount = 0;
    runDone = 0;
    _active = 0;
    runTotal = _queue.length;
    _runWatch
      ..reset()
      ..start();
    notifyListeners();
    await BackgroundService.start(
      title: 'Analizando canciones…',
      text: '',
      progress: 0,
      max: runTotal,
    );
    _pump();
  }

  /// Arranca analisis hasta llenar [workerLimit]; cuando no queda nada
  /// activo ni en cola, cierra la corrida.
  void _pump() {
    if (!running || _finishing) return;
    while (!_stop && _active < workerLimit && _queue.isNotEmpty) {
      final item = _queue.removeAt(0);
      _active++;
      unawaited(
        _process(item).whenComplete(() {
          _active--;
          _pump();
        }),
      );
    }
    runTotal = runDone + _active + _queue.length;
    final now = DateTime.now();
    if (now.difference(_lastServiceUpdate).inMilliseconds > 700) {
      _lastServiceUpdate = now;
      unawaited(
        BackgroundService.update(
          title: 'Analizando $runDone de $runTotal',
          text: currentName ?? '',
          progress: runDone,
          max: runTotal,
        ),
      );
    }
    if (_active == 0 && (_queue.isEmpty || _stop)) unawaited(_finishRun());
  }

  Future<void> _process(Item item) async {
    item.state = ItemState.running;
    currentName = item.name;
    _notifySoon();
    try {
      final d = await analyzer.analyze(item.path);
      item.data = d;
      item.error = null;
      item.state = ItemState.done;
      _okCount++;
      if (!item.temp) _unsaved++;
    } catch (e) {
      if (_stop) {
        if (item.data == null) {
          _items.remove(item.path);
        } else {
          item.state = ItemState.done;
        }
        return;
      }
      item.error = e.toString().replaceFirst('Exception: ', '');
      item.state = ItemState.error;
      _errCount++;
    }
    runDone++;
    _notifySoon();
    if (_unsaved >= 50) unawaited(_save());
  }

  Future<void> _finishRun() async {
    if (_finishing) return;
    _finishing = true;
    final cancelled = _stop;
    if (cancelled) {
      for (final item in _queue) {
        if (item.data == null) {
          _items.remove(item.path);
        } else {
          item.state = ItemState.done;
        }
      }
      _queue.clear();
    }
    currentName = null;
    try {
      await _save();
      if (cancelled) {
        await BackgroundService.stop();
      } else {
        await BackgroundService.finish(
          title: 'Análisis terminado',
          text:
              '${_okCount == 1 ? '1 canción analizada' : '$_okCount canciones analizadas'}'
              '${_errCount > 0 ? ' · $_errCount con error' : ''}',
        );
      }
    } finally {
      _runWatch.stop();
      _notifyTimer?.cancel();
      _notifyTimer = null;
      running = false;
      _finishing = false;
      notifyListeners();
    }
    // Si llegaron canciones mientras se cerraba, arranca otra corrida.
    if (_queue.isNotEmpty) unawaited(_runQueue());
  }

  Future<void> stop() async {
    _stop = true;
    notifyListeners();
    await analyzer.cancelAll();
    // Si no habia nada activo, _pump cierra la corrida de inmediato.
    _pump();
  }

  /// Reanaliza una cancion ahora mismo (sin pasar por la cola).
  Future<bool> reanalyze(Item item) async {
    final previous = item.state;
    item.state = ItemState.running;
    notifyListeners();
    try {
      item.data = await analyzer.analyze(item.path);
      item.error = null;
      item.state = ItemState.done;
      if (!item.temp) await _save();
      notifyListeners();
      return true;
    } catch (e) {
      item.error = e.toString().replaceFirst('Exception: ', '');
      item.state = item.data != null ? ItemState.done : previous;
      notifyListeners();
      return false;
    }
  }

  /// Reintenta una cancion con error.
  Future<void> retry(Item item) async {
    if (item.state != ItemState.error) return;
    item.state = ItemState.waiting;
    _queue.add(item);
    notifyListeners();
    unawaited(_runQueue());
  }

  /// Guardados encadenados: nunca dos escrituras al mismo tiempo.
  Future<void> _save() {
    _unsaved = 0;
    return _saveChain = _saveChain
        .then((_) => _doSave())
        .catchError((Object _) {});
  }

  Future<void> _doSave() async {
    final map = <String, StoredResult>{};
    for (final i in _items.values) {
      if (i.temp || i.state != ItemState.done || i.data == null) continue;
      map[i.path] = StoredResult(data: i.data!, size: i.size, mtime: i.mtime);
    }
    await ResultsStore.save(map);
  }

  Future<void> clearAll() async {
    if (running) return;
    _items.clear();
    await ResultsStore.clear();
    notifyListeners();
  }

  LibrarySummary summary() {
    var n = 0;
    var drSum = 0.0;
    var lufsSum = 0.0;
    var lufsN = 0;
    var sus = 0;
    for (final i in _items.values) {
      final d = i.data;
      if (i.state != ItemState.done || d == null) continue;
      n++;
      drSum += d.dynamicRange;
      if (d.integratedLufs != null) {
        lufsSum += d.integratedLufs!;
        lufsN++;
      }
      if (suspicionOf(d) != null) sus++;
    }
    return LibrarySummary(
      analyzed: n,
      avgDr: n > 0 ? drSum / n : null,
      avgLufs: lufsN > 0 ? lufsSum / lufsN : null,
      suspicious: sus,
    );
  }

  List<Item> view({
    String query = '',
    LibFilter filter = LibFilter.all,
    SortKey sort = SortKey.name,
    bool ascending = true,
  }) {
    final q = query.trim().toLowerCase();
    final list = _items.values.where((i) {
      if (q.isNotEmpty && !i.nameLower.contains(q)) return false;
      if (filter == LibFilter.all) return true;
      final d = i.data;
      if (d == null) return false;
      if (filter == LibFilter.suspicious) return suspicionOf(d) != null;
      return isCompressed(d);
    }).toList();

    int cmpNum(double? a, double? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1; // sin dato siempre al final
      if (b == null) return -1;
      return ascending ? a.compareTo(b) : b.compareTo(a);
    }

    list.sort((a, b) {
      switch (sort) {
        case SortKey.name:
          final c = a.nameLower.compareTo(b.nameLower);
          return ascending ? c : -c;
        case SortKey.dr:
          return cmpNum(a.data?.dynamicRange, b.data?.dynamicRange);
        case SortKey.lufs:
          return cmpNum(a.data?.integratedLufs, b.data?.integratedLufs);
        case SortKey.cutoff:
          return cmpNum(a.data?.spectralCutoffHz, b.data?.spectralCutoffHz);
      }
    });
    return list;
  }

  static String _csv(Object? v) {
    final s = v?.toString() ?? '';
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  /// Escribe un CSV con todos los resultados y devuelve su ruta.
  Future<String?> exportCsv() async {
    final rows = _items.values
        .where((i) => i.state == ItemState.done && i.data != null)
        .toList()
      ..sort((a, b) => a.nameLower.compareTo(b.nameLower));
    if (rows.isEmpty) return null;
    final b = StringBuffer('\uFEFF');
    b.writeln(
      'archivo,ruta,codec,frecuencia_hz,bits,bitrate_kbps,canales,duracion_s,'
      'tamano_bytes,rango_dinamico_db,pico_db,rms_db,lufs,pico_real_dbtp,'
      'recorte_muestras,corte_espectral_hz,aviso',
    );
    for (final i in rows) {
      final d = i.data!;
      b.writeln(
        [
          i.name,
          i.path,
          d.codec,
          d.sampleRate,
          d.bitDepth,
          (d.bitrate / 1000).round(),
          d.channels,
          d.duration.toStringAsFixed(1),
          d.fileSize,
          d.dynamicRange.toStringAsFixed(2),
          d.peakAmplitude.toStringAsFixed(2),
          d.rmsLevel.toStringAsFixed(2),
          d.integratedLufs?.toStringAsFixed(1),
          d.truePeakDb?.toStringAsFixed(2),
          d.clippingSamples,
          d.spectralCutoffHz?.toStringAsFixed(0),
          suspicionOf(d),
        ].map(_csv).join(','),
      );
    }
    final tmp = await getTemporaryDirectory();
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}';
    final f = File('${tmp.path}/aztra_analyzer_$stamp.csv');
    await f.writeAsString(b.toString());
    return f.path;
  }
}
