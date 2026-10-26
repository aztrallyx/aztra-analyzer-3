// Tarjeta de analisis. Misma estructura y tamanos que la de Mornye.
import 'package:flutter/material.dart';

import 'audio_analysis_ffmpeg.dart';
import 'audio_analysis_models.dart';
import 'format.dart';
import 'glass.dart';

class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.data, this.onRescan});

  final AudioAnalysisData data;
  final VoidCallback? onRescan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nyquist = data.sampleRate / 2;

    return GlassCard(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Análisis de calidad de audio',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (onRescan != null)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Reanalizar',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    color: cs.onSurfaceVariant,
                    onPressed: onRescan,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (data.codec.isNotEmpty)
                  _MetricChip(
                    icon: Icons.memory,
                    label: 'Códec',
                    value: data.codec,
                    cs: cs,
                  ),
                if (data.container.isNotEmpty)
                  _MetricChip(
                    icon: Icons.inventory_2_outlined,
                    label: 'Contenedor',
                    value: data.container,
                    cs: cs,
                  ),
                _MetricChip(
                  icon: Icons.graphic_eq,
                  label: 'Frecuencia de muestreo',
                  value: '${(data.sampleRate / 1000).toStringAsFixed(1)} kHz',
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.audio_file,
                  label: 'Profundidad de bits',
                  value: data.bitDepth,
                  cs: cs,
                ),
                if (data.decodedSampleFormat.isNotEmpty)
                  _MetricChip(
                    icon: Icons.data_object,
                    label: 'Formato decodificado',
                    value: data.decodedSampleFormat,
                    cs: cs,
                  ),
                if (data.bitrate > 0)
                  _MetricChip(
                    icon: Icons.speed,
                    label: 'Tasa de bits',
                    value: _formatBitrate(data.bitrate),
                    cs: cs,
                  ),
                _MetricChip(
                  icon: Icons.surround_sound,
                  label: 'Canales',
                  value: _formatChannels(data),
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.timer_outlined,
                  label: 'Duración',
                  value: formatClock(data.duration),
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.multiline_chart,
                  label: 'Nyquist',
                  value: '${(nyquist / 1000).toStringAsFixed(1)} kHz',
                  cs: cs,
                ),
                if (data.fileSize > 0)
                  _MetricChip(
                    icon: Icons.storage,
                    label: 'Tamaño',
                    value: formatBytes(data.fileSize),
                    cs: cs,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _MetricChip(
                  icon: Icons.trending_up,
                  label: 'Rango dinámico',
                  value: '${data.dynamicRange.toStringAsFixed(2)} dB',
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.show_chart,
                  label: 'Pico',
                  value: '${data.peakAmplitude.toStringAsFixed(2)} dB',
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.equalizer,
                  label: 'RMS',
                  value: '${data.rmsLevel.toStringAsFixed(2)} dB',
                  cs: cs,
                ),
                if (data.integratedLufs != null)
                  _MetricChip(
                    icon: Icons.volume_up_outlined,
                    label: 'LUFS',
                    value: '${data.integratedLufs!.toStringAsFixed(1)} LUFS',
                    cs: cs,
                  ),
                if (data.truePeakDb != null)
                  _MetricChip(
                    icon: Icons.warning_amber_outlined,
                    label: 'Pico real',
                    value: '${data.truePeakDb!.toStringAsFixed(2)} dBTP',
                    cs: cs,
                  ),
                _MetricChip(
                  icon: Icons.report_gmailerrorred_outlined,
                  label: 'Recorte',
                  value: data.clippingSamples <= 0
                      ? 'Sin recortes'
                      : formatCount(data.clippingSamples),
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.filter_alt_outlined,
                  label: 'Corte espectral',
                  value: formatAudioAnalysisSpectralCutoff(
                    data.spectralCutoffHz,
                    notDetectedLabel: 'No detectado',
                  ),
                  cs: cs,
                ),
                _MetricChip(
                  icon: Icons.numbers,
                  label: 'Muestras',
                  value: formatCount(data.totalSamples),
                  cs: cs,
                ),
              ],
            ),
            if (data.channelStats.length > 1) ...[
              const SizedBox(height: 8),
              Divider(color: cs.outlineVariant),
              const SizedBox(height: 8),
              Text(
                'Estadísticas por canal',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: data.channelStats.map((stats) {
                  return _MetricChip(
                    icon: Icons.surround_sound,
                    label: 'Ch ${stats.channel}',
                    value: _formatChannelStats(stats),
                    cs: cs,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatChannels(AudioAnalysisData data) {
    final layout = data.channelLayout.trim();
    if (layout.isNotEmpty && layout != 'unknown') {
      return data.channels > 0 ? '${data.channels} ($layout)' : layout;
    }
    if (data.channels == 2) return '2 (stereo)';
    if (data.channels == 1) return '1 (mono)';
    return data.channels > 0 ? '${data.channels}' : 'N/A';
  }

  static String _formatBitrate(int bitsPerSecond) {
    if (bitsPerSecond >= 1000000) {
      return '${(bitsPerSecond / 1000000).toStringAsFixed(2)} Mbps';
    }
    return '${(bitsPerSecond / 1000).round()} kbps';
  }

  static String _formatChannelStats(ChannelAnalysisStats stats) {
    final parts = <String>[];
    if (stats.peakDb != null) {
      parts.add('P ${stats.peakDb!.toStringAsFixed(1)}');
    }
    if (stats.rmsDb != null) {
      parts.add('R ${stats.rmsDb!.toStringAsFixed(1)}');
    }
    if (stats.dynamicRangeDb != null) {
      parts.add('DR ${stats.dynamicRangeDb!.toStringAsFixed(1)}');
    }
    if (stats.peakCount > 0 && (stats.peakDb ?? -100) >= -0.1) {
      parts.add('Clip ${formatCount(stats.peakCount)}');
    }
    return parts.isEmpty ? 'N/A' : parts.join(' / ');
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.cs,
  });

  final IconData icon;
  final String label;
  final String value;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
