import 'audio_analysis_models.dart';
import 'library.dart';

/// Un grupo de canciones que parecen ser la misma.
class DuplicateGroup {
  DuplicateGroup({required this.items, required this.exact});

  /// Ordenadas de mejor a peor calidad: la primera es la sugerida.
  final List<Item> items;

  /// true = el audio decodificado es identico (mismos numeros al detalle).
  /// false = mismo master probable (misma duracion y niveles muy parecidos).
  final bool exact;

  Item get best => items.first;

  /// Espacio que ocuparian las copias sobrantes (todas menos la sugerida).
  int get extraBytes {
    var total = 0;
    for (var i = 1; i < items.length; i++) {
      total += items[i].size;
    }
    return total;
  }
}

const _lossless = {'flac', 'alac', 'wavpack', 'ape', 'tta'};

bool _isLossless(AudioAnalysisData d) {
  final c = d.codec.toLowerCase();
  return _lossless.contains(c) || c.startsWith('pcm_');
}

/// Mayor = mejor calidad: lossless, mas bits, mas frecuencia, mas bitrate.
int compareQuality(Item a, Item b) {
  final x = a.data!;
  final y = b.data!;
  final l = (_isLossless(y) ? 1 : 0) - (_isLossless(x) ? 1 : 0);
  if (l != 0) return l;
  if (x.bitsPerSample != y.bitsPerSample) {
    return y.bitsPerSample.compareTo(x.bitsPerSample);
  }
  if (x.sampleRate != y.sampleRate) return y.sampleRate.compareTo(x.sampleRate);
  if (x.bitrate != y.bitrate) return y.bitrate.compareTo(x.bitrate);
  return b.size.compareTo(a.size);
}

bool _close(double? a, double? b, double tol) {
  if (a == null || b == null) return a == b;
  return (a - b).abs() <= tol;
}

bool _sameAudio(AudioAnalysisData a, AudioAnalysisData b) {
  return a.totalSamples > 0 &&
      a.totalSamples == b.totalSamples &&
      a.sampleRate == b.sampleRate &&
      a.channels == b.channels &&
      _close(a.peakAmplitude, b.peakAmplitude, 0.005) &&
      _close(a.rmsLevel, b.rmsLevel, 0.005) &&
      _close(a.integratedLufs, b.integratedLufs, 0.05);
}

bool _sameMaster(AudioAnalysisData a, AudioAnalysisData b) {
  return a.channels == b.channels &&
      (a.duration - b.duration).abs() <= 0.6 &&
      _close(a.integratedLufs, b.integratedLufs, 0.3) &&
      _close(a.rmsLevel, b.rmsLevel, 0.3) &&
      _close(a.peakAmplitude, b.peakAmplitude, 1.0);
}

/// Busca canciones repetidas usando solo los numeros ya analizados. No lee
/// los archivos otra vez ni compara el contenido: por eso las del segundo tipo
/// son "probables" y conviene revisarlas con la pantalla de comparar.
List<DuplicateGroup> findDuplicates(List<Item> all) {
  final items = all
      .where(
        (i) =>
            i.state == ItemState.done &&
            i.data != null &&
            i.data!.duration >= 10,
      )
      .toList()
    ..sort((a, b) => a.data!.duration.compareTo(b.data!.duration));
  final n = items.length;
  final parent = List<int>.generate(n, (i) => i);

  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) parent[rb] = ra;
  }

  for (var i = 0; i < n; i++) {
    final a = items[i].data!;
    for (var j = i + 1; j < n; j++) {
      final b = items[j].data!;
      if (b.duration - a.duration > 0.6) break;
      if (_sameAudio(a, b) || _sameMaster(a, b)) union(i, j);
    }
  }

  final byRoot = <int, List<Item>>{};
  for (var i = 0; i < n; i++) {
    byRoot.putIfAbsent(find(i), () => []).add(items[i]);
  }

  final groups = <DuplicateGroup>[];
  for (final members in byRoot.values) {
    if (members.length < 2) continue;
    members.sort(compareQuality);
    final first = members.first.data!;
    final exact = members.skip(1).every((m) => _sameAudio(first, m.data!));
    groups.add(DuplicateGroup(items: members, exact: exact));
  }
  groups.sort((a, b) {
    if (a.exact != b.exact) return a.exact ? -1 : 1;
    return b.extraBytes.compareTo(a.extraBytes);
  });
  return groups;
}
