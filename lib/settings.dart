import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class AppSettings extends ChangeNotifier {
  /// 'google_sans_flex' (como Mornye), 'inter', 'system' o 'custom'.
  String font = 'google_sans_flex';

  /// Tope de la cache de espectrogramas en MB. 0 = apagada.
  int spectrogramBudgetMb = 64;

  /// Canciones que se analizan a la vez. 0 = automatico segun el telefono.
  int analysisParallelism = 0;

  /// Fuente propia: archivo copiado dentro de la app y su nombre original.
  String? customFontFile;
  String? customFontLabel;
  bool customLoaded = false;
  int _customVersion = 0;

  String? get fontFamily {
    switch (font) {
      case 'inter':
        return 'Inter';
      case 'system':
        return null;
      case 'custom':
        return customLoaded
            ? 'AztraCustom$_customVersion'
            : 'Google Sans Flex';
      default:
        return 'Google Sans Flex';
    }
  }

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/settings.json');
  }

  static Future<Directory> _fontDir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/fonts');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<AppSettings> load() async {
    final s = AppSettings();
    try {
      final f = await _file();
      if (await f.exists()) {
        final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final font = json['font'] as String?;
        if (font == 'google_sans_flex' ||
            font == 'inter' ||
            font == 'system' ||
            font == 'custom') {
          s.font = font!;
        }
        final budget = json['spectrogramBudgetMb'];
        if (budget is int && budget >= 0) s.spectrogramBudgetMb = budget;
        final par = json['analysisParallelism'];
        if (par is int && par >= 0 && par <= 4) s.analysisParallelism = par;
        s.customFontFile = json['customFontFile'] as String?;
        s.customFontLabel = json['customFontLabel'] as String?;
      }
    } catch (_) {}
    if (s.customFontFile != null) await s.loadCustomFont();
    if (s.font == 'custom' && !s.customLoaded) s.font = 'google_sans_flex';
    return s;
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(
        jsonEncode({
          'font': font,
          'spectrogramBudgetMb': spectrogramBudgetMb,
          'analysisParallelism': analysisParallelism,
          'customFontFile': customFontFile,
          'customFontLabel': customFontLabel,
        }),
      );
    } catch (_) {}
  }

  /// Carga en memoria la fuente propia guardada.
  Future<void> loadCustomFont() async {
    customLoaded = false;
    final name = customFontFile;
    if (name == null) return;
    try {
      final dir = await _fontDir();
      final f = File('${dir.path}/$name');
      if (!await f.exists()) return;
      final bytes = await f.readAsBytes();
      if (bytes.length < 12) return;
      _customVersion++;
      final loader = FontLoader('AztraCustom$_customVersion')
        ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
      await loader.load();
      customLoaded = true;
    } catch (_) {
      customLoaded = false;
    }
  }

  /// Copia el archivo elegido a la app, lo carga y lo activa.
  /// Devuelve false si no es una fuente valida (.ttf / .otf).
  Future<bool> importCustomFont(String sourcePath, String label) async {
    final lower = sourcePath.toLowerCase();
    final ext = lower.endsWith('.otf') ? '.otf' : (lower.endsWith('.ttf') ? '.ttf' : null);
    if (ext == null) return false;
    try {
      final dir = await _fontDir();
      final newName = 'custom_${DateTime.now().millisecondsSinceEpoch}$ext';
      await File(sourcePath).copy('${dir.path}/$newName');
      final oldName = customFontFile;
      final oldLabel = customFontLabel;
      customFontFile = newName;
      customFontLabel = label;
      await loadCustomFont();
      if (!customLoaded) {
        try {
          await File('${dir.path}/$newName').delete();
        } catch (_) {}
        customFontFile = oldName;
        customFontLabel = oldLabel;
        if (oldName != null) await loadCustomFont();
        return false;
      }
      if (oldName != null && oldName != newName) {
        try {
          await File('${dir.path}/$oldName').delete();
        } catch (_) {}
      }
      font = 'custom';
      notifyListeners();
      await _save();
      return true;
    } catch (_) {
      return false;
    }
  }

  void setFont(String value) {
    if (value == 'custom' && !customLoaded) return;
    font = value;
    notifyListeners();
    _save();
  }

  void setAnalysisParallelism(int value) {
    analysisParallelism = value;
    notifyListeners();
    _save();
  }

  void setSpectrogramBudgetMb(int value) {
    spectrogramBudgetMb = value;
    notifyListeners();
    _save();
  }
}
