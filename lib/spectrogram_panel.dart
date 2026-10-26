import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'library.dart';
import 'settings.dart';
import 'spectrogram_card.dart';
import 'store.dart';

/// Espectrograma de una cancion (canales combinados) que se carga solo.
/// Usa la cache y, si no esta, lo genera. Se usa en la pantalla de comparar.
class SpectrogramPanel extends StatefulWidget {
  const SpectrogramPanel({
    super.key,
    required this.item,
    required this.controller,
    required this.settings,
  });

  final Item item;
  final LibraryController controller;
  final AppSettings settings;

  @override
  State<SpectrogramPanel> createState() => _SpectrogramPanelState();
}

class _SpectrogramPanelState extends State<SpectrogramPanel> {
  ui.Image? _image;
  bool _loading = true;
  String? _error;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final item = widget.item;
      final data = item.data!;
      ui.Image? img = await SpectrogramCache.load(item.cacheKey, -1);
      if (_disposed) {
        img?.dispose();
        return;
      }
      if (img == null) {
        if (!await File(item.path).exists()) {
          throw Exception('No encuentro el archivo.');
        }
        img = await widget.controller.analyzer.generateSpectrogram(
          item.path,
          data,
        );
        if (_disposed) {
          img.dispose();
          return;
        }
        final budget = widget.settings.spectrogramBudgetMb * 1024 * 1024;
        unawaited(SpectrogramCache.save(item.cacheKey, -1, img, budget));
      }
      setState(() {
        _image = img;
        _loading = false;
      });
    } catch (e) {
      if (_disposed) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.item.data!;
    return SpectrogramCard(
      image: _image,
      loading: _loading,
      errorText: _error,
      sampleRate: d.sampleRate,
      duration: d.duration,
      channels: 1,
      selectedChannel: -1,
      onChannelChanged: (_) {},
      onSave: null,
    );
  }
}
