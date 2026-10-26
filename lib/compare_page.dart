import 'package:flutter/material.dart';

import 'audio_analysis_ffmpeg.dart';
import 'audio_analysis_models.dart';
import 'format.dart';
import 'library.dart';
import 'pick_song_page.dart';
import 'settings.dart';
import 'spectrogram_panel.dart';

/// Compara dos canciones ya analizadas: numeros lado a lado, un resumen en
/// palabras y los dos espectrogramas.
class ComparePage extends StatefulWidget {
  const ComparePage({
    super.key,
    required this.controller,
    required this.settings,
    this.a,
    this.b,
  });

  final LibraryController controller;
  final AppSettings settings;
  final Item? a;
  final Item? b;

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  Item? _a;
  Item? _b;

  @override
  void initState() {
    super.initState();
    _a = widget.a;
    _b = widget.b;
  }

  Future<void> _pick(bool isA) async {
    final picked = await Navigator.of(context).push<Item>(
      MaterialPageRoute(
        builder: (_) => PickSongPage(
          controller: widget.controller,
          title: isA ? 'Elegir canción A' : 'Elegir canción B',
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isA) {
        _a = picked;
      } else {
        _b = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = _a;
    final b = _b;
    return Scaffold(
      appBar: AppBar(title: const Text('Comparar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: _Slot(label: 'A', item: a, onTap: () => _pick(true)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Slot(label: 'B', item: b, onTap: () => _pick(false)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (a == null || b == null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Elige dos canciones ya analizadas para compararlas.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          else ...[
            _InsightsCard(a: a.data!, b: b.data!),
            const SizedBox(height: 12),
            _TableCard(a: a.data!, b: b.data!),
            const SizedBox(height: 16),
            _Label('A · ${a.name}'),
            SpectrogramPanel(
              key: ValueKey('spec-a-${a.path}'),
              item: a,
              controller: widget.controller,
              settings: widget.settings,
            ),
            const SizedBox(height: 16),
            _Label('B · ${b.name}'),
            SpectrogramPanel(
              key: ValueKey('spec-b-${b.path}'),
              item: b,
              controller: widget.controller,
              settings: widget.settings,
            ),
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.label, required this.item, required this.onTap});
  final String label;
  final Item? item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Canción $label',
                style: TextStyle(
                  color: cs.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item?.name ?? 'Toca para elegir',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: item == null ? cs.onSurfaceVariant : cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _kHz(double? hz) =>
    hz == null ? 'No detectado' : '${(hz / 1000).toStringAsFixed(1)} kHz';

List<String> _insights(AudioAnalysisData a, AudioAnalysisData b) {
  final out = <String>[];

  final dr = b.dynamicRange - a.dynamicRange;
  if (dr.abs() >= 0.5) {
    out.add(
      '${dr > 0 ? 'B' : 'A'} tiene ${dr.abs().toStringAsFixed(1)} dB más de '
      'rango dinámico (suena menos comprimida).',
    );
  } else {
    out.add('El rango dinámico es casi igual (diferencia de ${dr.abs().toStringAsFixed(1)} dB).');
  }

  final la = a.integratedLufs;
  final lb = b.integratedLufs;
  if (la != null && lb != null) {
    final d = lb - la;
    if (d.abs() >= 0.5) {
      out.add(
        '${d > 0 ? 'B' : 'A'} suena ${d.abs().toStringAsFixed(1)} dB más fuerte '
        '(LUFS). Ojo: si no igualas el volumen, la más fuerte suele parecer mejor.',
      );
    } else {
      out.add('El volumen (LUFS) es casi igual.');
    }
  }

  final ca = a.spectralCutoffHz;
  final cb = b.spectralCutoffHz;
  if (ca != null && cb != null && (ca - cb).abs() >= 1000) {
    out.add(
      'El corte espectral cambia: A llega hasta ${_kHz(ca)} y B hasta ${_kHz(cb)}.',
    );
  }

  if (a.sampleRate != b.sampleRate || a.bitDepth != b.bitDepth) {
    out.add(
      'Formato distinto: A es ${a.codec} ${(a.sampleRate / 1000).toStringAsFixed(1)} kHz '
      '${a.bitDepth}, B es ${b.codec} ${(b.sampleRate / 1000).toStringAsFixed(1)} kHz ${b.bitDepth}.',
    );
  }

  if ((a.clippingSamples > 0) != (b.clippingSamples > 0)) {
    out.add('${a.clippingSamples > 0 ? 'A' : 'B'} tiene recortes y la otra no.');
  }

  if ((a.duration - b.duration).abs() >= 1) {
    out.add(
      'Duran distinto: A ${formatClock(a.duration)} y B ${formatClock(b.duration)}.',
    );
  }
  return out;
}

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.a, required this.b});
  final AudioAnalysisData a;
  final AudioAnalysisData b;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = _insights(a, b);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resumen',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(child: Text(l, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.a, required this.b});
  final AudioAnalysisData a;
  final AudioAnalysisData b;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String delta(double? x, double? y, String unit, {int digits = 1}) {
      if (x == null || y == null) return '';
      final d = y - x;
      if (d.abs() < 0.05) return '=';
      return '${d > 0 ? '+' : ''}${d.toStringAsFixed(digits)} $unit';
    }

    final rows = <List<String>>[
      ['Códec', a.codec, b.codec, ''],
      [
        'Frecuencia',
        '${(a.sampleRate / 1000).toStringAsFixed(1)} kHz',
        '${(b.sampleRate / 1000).toStringAsFixed(1)} kHz',
        '',
      ],
      ['Bits', a.bitDepth, b.bitDepth, ''],
      [
        'Tasa de bits',
        '${(a.bitrate / 1000).round()} kbps',
        '${(b.bitrate / 1000).round()} kbps',
        '',
      ],
      ['Duración', formatClock(a.duration), formatClock(b.duration), ''],
      ['Tamaño', formatBytes(a.fileSize), formatBytes(b.fileSize), ''],
      [
        'Rango dinámico',
        '${a.dynamicRange.toStringAsFixed(2)} dB',
        '${b.dynamicRange.toStringAsFixed(2)} dB',
        delta(a.dynamicRange, b.dynamicRange, 'dB'),
      ],
      [
        'Pico',
        '${a.peakAmplitude.toStringAsFixed(2)} dB',
        '${b.peakAmplitude.toStringAsFixed(2)} dB',
        delta(a.peakAmplitude, b.peakAmplitude, 'dB'),
      ],
      [
        'RMS',
        '${a.rmsLevel.toStringAsFixed(2)} dB',
        '${b.rmsLevel.toStringAsFixed(2)} dB',
        delta(a.rmsLevel, b.rmsLevel, 'dB'),
      ],
      [
        'LUFS',
        a.integratedLufs == null ? '—' : a.integratedLufs!.toStringAsFixed(1),
        b.integratedLufs == null ? '—' : b.integratedLufs!.toStringAsFixed(1),
        delta(a.integratedLufs, b.integratedLufs, 'LU'),
      ],
      [
        'Pico real',
        a.truePeakDb == null ? '—' : '${a.truePeakDb!.toStringAsFixed(2)} dBTP',
        b.truePeakDb == null ? '—' : '${b.truePeakDb!.toStringAsFixed(2)} dBTP',
        delta(a.truePeakDb, b.truePeakDb, 'dB', digits: 2),
      ],
      [
        'Recorte',
        a.clippingSamples <= 0 ? 'Sin recortes' : formatCount(a.clippingSamples),
        b.clippingSamples <= 0 ? 'Sin recortes' : formatCount(b.clippingSamples),
        '',
      ],
      [
        'Corte espectral',
        formatAudioAnalysisSpectralCutoff(
          a.spectralCutoffHz,
          notDetectedLabel: 'No detectado',
        ),
        formatAudioAnalysisSpectralCutoff(
          b.spectralCutoffHz,
          notDetectedLabel: 'No detectado',
        ),
        '',
      ],
    ];

    TextStyle head = TextStyle(
      color: cs.primary,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    TextStyle label = TextStyle(color: cs.onSurfaceVariant, fontSize: 12);
    const value = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(flex: 4, child: SizedBox()),
                Expanded(flex: 4, child: Text('A', style: head)),
                Expanded(flex: 4, child: Text('B', style: head)),
                Expanded(
                  flex: 3,
                  child: Text('B − A', style: head, textAlign: TextAlign.end),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(flex: 4, child: Text(r[0], style: label)),
                    Expanded(flex: 4, child: Text(r[1], style: value)),
                    Expanded(flex: 4, child: Text(r[2], style: value)),
                    Expanded(
                      flex: 3,
                      child: Text(
                        r[3],
                        style: label,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
