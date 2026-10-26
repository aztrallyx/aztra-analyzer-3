import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'format.dart';
import 'library.dart';
import 'settings.dart';
import 'store.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.settings,
  });

  final LibraryController controller;
  final AppSettings settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _refresh = 0;

  AppSettings get _s => widget.settings;

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _choice({
    required String title,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) => ListTile(
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing: selected ? const Icon(Icons.check) : null,
    onTap: onTap,
  );

  Future<void> _pickCustomFont() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final file = res?.files.single;
    final path = file?.path;
    if (file == null || path == null) return;
    final ok = await _s.importCustomFont(path, file.name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Fuente aplicada: ${file.name}'
              : 'No pude usar ese archivo. Elige una fuente .ttf u .otf.',
        ),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar resultados guardados?'),
        content: const Text(
          'Se borran los números de todas las canciones analizadas. '
          'Tendrás que volver a analizar tus carpetas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.controller.clearAll();
    if (mounted) setState(() => _refresh++);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Ajustes')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _section('Fuente'),
              _choice(
                title: 'Google Sans Flex',
                subtitle: 'La misma que usa Mornye',
                selected: _s.font == 'google_sans_flex',
                onTap: () => _s.setFont('google_sans_flex'),
              ),
              _choice(
                title: 'Inter',
                selected: _s.font == 'inter',
                onTap: () => _s.setFont('inter'),
              ),
              _choice(
                title: 'Del sistema',
                subtitle: 'La fuente de tu teléfono',
                selected: _s.font == 'system',
                onTap: () => _s.setFont('system'),
              ),
              _choice(
                title: 'Mi fuente',
                subtitle: _s.customLoaded
                    ? _s.customFontLabel
                    : 'Toca para elegir un archivo .ttf u .otf',
                selected: _s.font == 'custom',
                onTap: () =>
                    _s.customLoaded ? _s.setFont('custom') : _pickCustomFont(),
              ),
              if (_s.customLoaded)
                ListTile(
                  title: const Text('Cambiar mi fuente…'),
                  subtitle: const Text('Elige otro archivo .ttf u .otf'),
                  trailing: const Icon(Icons.upload_file_outlined),
                  onTap: _pickCustomFont,
                ),
              _section('Velocidad de análisis'),
              for (final n in const [0, 1, 2, 3, 4])
                _choice(
                  title: n == 0
                      ? 'Automático'
                      : n == 1
                      ? '1 canción a la vez'
                      : '$n canciones a la vez',
                  subtitle: n == 0
                      ? 'Recomendado. Se ajusta a los núcleos del teléfono'
                      : n == 4
                      ? 'Más rápido, pero calienta y gasta más batería'
                      : null,
                  selected: _s.analysisParallelism == n,
                  onTap: () => _s.setAnalysisParallelism(n),
                ),
              _section('Espectrogramas guardados'),
              for (final mb in const [0, 32, 64, 128])
                _choice(
                  title: mb == 0 ? 'No guardar' : 'Hasta $mb MB',
                  subtitle: mb == 0
                      ? 'Se generan cada vez que abres una canción'
                      : mb == 64
                      ? 'Recomendado. Borra los más viejos al pasarse'
                      : null,
                  selected: _s.spectrogramBudgetMb == mb,
                  onTap: () => _s.setSpectrogramBudgetMb(mb),
                ),
              FutureBuilder<int>(
                key: ValueKey('spec$_refresh'),
                future: SpectrogramCache.sizeBytes(),
                builder: (context, snap) => ListTile(
                  title: const Text('Borrar espectrogramas guardados'),
                  subtitle: Text(
                    'Ocupan ${formatBytes(snap.data ?? 0)} ahora mismo',
                  ),
                  trailing: const Icon(Icons.delete_outline),
                  onTap: () async {
                    await SpectrogramCache.clear();
                    if (mounted) setState(() => _refresh++);
                  },
                ),
              ),
              _section('Resultados guardados'),
              FutureBuilder<int>(
                key: ValueKey('store$_refresh'),
                future: ResultsStore.sizeBytes(),
                builder: (context, snap) => ListTile(
                  title: const Text('Borrar todos los resultados'),
                  subtitle: Text(
                    '${widget.controller.totalItems} canciones · '
                    '${formatBytes(snap.data ?? 0)}',
                  ),
                  trailing: const Icon(Icons.delete_outline),
                  onTap: _confirmClear,
                ),
              ),
              _section('Permisos'),
              ListTile(
                title: const Text('Acceso a todos los archivos'),
                subtitle: const Text(
                  'Solo si la app no encuentra canciones en una carpeta',
                ),
                onTap: () => Permission.manageExternalStorage.request(),
              ),
              _section('Acerca de'),
              ListTile(
                title: const Text('Aztra Analyzer 2.0'),
                subtitle: const Text(
                  'Analizador basado en el de Mornye (LGPL-3.0). '
                  'Fuentes Google Sans Flex e Inter (SIL OFL).',
                ),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Aztra Analyzer',
                  applicationVersion: '2.0.0',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
