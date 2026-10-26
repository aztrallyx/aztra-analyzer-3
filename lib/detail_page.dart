import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'audio_analysis_models.dart';
import 'info_card.dart';
import 'library.dart';
import 'settings.dart';
import 'spectrogram_card.dart';
import 'store.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.item,
    required this.controller,
    required this.settings,
  });

  final Item item;
  final LibraryController controller;
  final AppSettings settings;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late AudioAnalysisData _data = widget.item.data!;
  ui.Image? _image;
  int _channel = -1;
  bool _loading = true;
  String? _error;
  int _req = 0;
  bool _rescanning = false;

  @override
  void initState() {
    super.initState();
    _loadSpectrogram(-1);
  }

  @override
  void dispose() {
    _req++;
    _image?.dispose();
    super.dispose();
  }

  Future<void> _loadSpectrogram(int channel) async {
    final req = ++_req;
    setState(() {
      _loading = true;
      _error = null;
      _channel = channel;
    });
    try {
      final item = widget.item;
      final key = item.cacheKey;
      ui.Image? img = await SpectrogramCache.load(key, channel);
      if (req != _req || !mounted) {
        img?.dispose();
        return;
      }
      if (img == null) {
        if (!await File(item.path).exists()) {
          throw Exception(
            'No encuentro el archivo. Si lo moviste o lo borraste, '
            'vuelve a agregarlo.',
          );
        }
        img = await widget.controller.analyzer.generateSpectrogram(
          item.path,
          _data,
          channel: channel,
        );
        if (req != _req || !mounted) {
          img.dispose();
          return;
        }
        final budget = widget.settings.spectrogramBudgetMb * 1024 * 1024;
        unawaited(SpectrogramCache.save(key, channel, img, budget));
      }
      final old = _image;
      setState(() {
        _image = img;
        _loading = false;
      });
      old?.dispose();
    } catch (e) {
      if (req != _req || !mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _rescan() async {
    setState(() => _rescanning = true);
    final ok = await widget.controller.reanalyze(widget.item);
    if (!mounted) return;
    setState(() {
      _rescanning = false;
      if (ok) _data = widget.item.data!;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.item.error ?? 'No se pudo reanalizar')),
      );
    }
  }

  Future<void> _shareSpectrogram() async {
    final img = _image;
    if (img == null) return;
    try {
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return;
      final tmp = await getTemporaryDirectory();
      final base = widget.item.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      final safe = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final suffix = _channel < 0 ? '' : '_ch${_channel + 1}';
      final f = File('${tmp.path}/${safe}_espectrograma$suffix.png');
      await f.writeAsBytes(bd.buffer.asUint8List());
      await Share.shareXFiles([XFile(f.path)]);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pude guardar el espectrograma')),
      );
    }
  }

  Future<void> _copySummary() async {
    final d = _data;
    final text = StringBuffer()
      ..writeln(widget.item.name)
      ..writeln(
        '${d.codec} · ${(d.sampleRate / 1000).toStringAsFixed(1)} kHz · '
        '${d.bitDepth} · ${(d.bitrate / 1000).round()} kbps',
      )
      ..writeln(
        'DR ${d.dynamicRange.toStringAsFixed(2)} dB · '
        'Pico ${d.peakAmplitude.toStringAsFixed(2)} dB · '
        'RMS ${d.rmsLevel.toStringAsFixed(2)} dB',
      )
      ..writeln(
        'LUFS ${d.integratedLufs?.toStringAsFixed(1) ?? '—'} · '
        'Pico real ${d.truePeakDb?.toStringAsFixed(2) ?? '—'} dBTP',
      )
      ..writeln(
        'Corte espectral: ${d.spectralCutoffHz == null ? 'No detectado' : '${(d.spectralCutoffHz! / 1000).toStringAsFixed(1)} kHz'}',
      );
    await Clipboard.setData(ClipboardData(text: text.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Datos copiados')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sus = suspicionOf(_data);
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(6),
          child: IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: cs.surfaceContainer,
              foregroundColor: cs.onSurface,
            ),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        title: const Text('Información'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'rescan') _rescan();
                if (v == 'copy') _copySummary();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rescan', child: Text('Reanalizar')),
                PopupMenuItem(value: 'copy', child: Text('Copiar datos')),
              ],
              child: CircleAvatar(
                radius: 20,
                backgroundColor: cs.surfaceContainer,
                child: Icon(Icons.more_horiz, color: cs.onSurface),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              widget.item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          if (sus != null) ...[
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: cs.errorContainer.withValues(alpha: 0.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: cs.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(sus, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          InfoCard(data: _data, onRescan: _rescanning ? null : _rescan),
          if (_rescanning)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          const SizedBox(height: 16),
          SpectrogramCard(
            image: _image,
            loading: _loading,
            errorText: _error,
            sampleRate: _data.sampleRate,
            duration: _data.duration,
            channels: _data.channels,
            selectedChannel: _channel,
            onChannelChanged: _loadSpectrogram,
            onSave: _shareSpectrogram,
          ),
        ],
      ),
    );
  }
}
