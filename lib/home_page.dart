
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import 'audio_analysis_ffmpeg.dart';
import 'audio_analysis_models.dart';
import 'background.dart';
import 'compare_page.dart';
import 'detail_page.dart';
import 'duplicates_page.dart';
import 'format.dart';
import 'library.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'glass.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller, required this.settings});

  final LibraryController controller;
  final AppSettings settings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  LibFilter _filter = LibFilter.all;
  SortKey _sort = SortKey.name;
  bool _ascending = true;

  LibraryController get _c => widget.controller;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  Future<bool> _ensureAudioPermission() async {
    var status = await Permission.audio.request();
    if (status.isGranted) return true;
    status = await Permission.storage.request();
    if (status.isGranted) return true;
    _snack(
      'Necesito permiso para leer tus audios.',
      action: SnackBarAction(label: 'Abrir ajustes', onPressed: openAppSettings),
    );
    return false;
  }

  Future<void> _pickFolder() async {
    if (!await _ensureAudioPermission()) return;
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    await Permission.notification.request();
    final r = await _c.addFolder(dir);
    if (r.found == 0) {
      _snack(
        'No encontré audios en esa carpeta. Si sí hay, prueba dar acceso a '
        'todos los archivos.',
        action: SnackBarAction(
          label: 'Dar acceso',
          onPressed: () => Permission.manageExternalStorage.request(),
        ),
      );
    } else if (r.added == 0) {
      _snack('Encontré ${r.found} canciones y todas ya estaban analizadas.');
    } else {
      _snack('Analizando ${r.added} canciones (${r.found} encontradas).');
    }
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    if (res == null) return;
    await Permission.notification.request();
    final paths = res.files.map((f) => f.path).whereType<String>();
    final added = await _c.addPaths(paths, temp: true);
    if (added == 0) _snack('Esos archivos no parecen audio, o ya están en la lista.');
  }

  void _showAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Carpeta'),
              subtitle: const Text(
                'Analiza todo lo que haya adentro y guarda los resultados',
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickFolder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: const Text('Archivos sueltos'),
              subtitle: const Text('Temporales: no se guardan al cerrar la app'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickFiles();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    final path = await _c.exportCsv();
    if (path == null) {
      _snack('Todavía no hay resultados para exportar.');
      return;
    }
    await Share.shareXFiles([XFile(path)]);
  }

  void _open(Item item) {
    if (item.state == ItemState.error) {
      _c.retry(item);
      return;
    }
    if (item.state != ItemState.done || item.data == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailPage(
          item: item,
          controller: _c,
          settings: widget.settings,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_c, _searchCtrl]),
      builder: (context, _) {
        final items = _c.view(
          query: _searchCtrl.text,
          filter: _filter,
          sort: _sort,
          ascending: _ascending,
        );
        final summary = _c.summary();
        final cs = Theme.of(context).colorScheme;
        final empty = _c.totalItems == 0 && !_c.scanning;

        return PopScope(
          canPop: !_c.running,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) BackgroundService.moveToBack();
          },
          child: Scaffold(
          appBar: AppBar(
            title: _searching
                ? TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Buscar canción',
                      border: InputBorder.none,
                    ),
                  )
                : const Text('Aztra Analyzer'),
            actions: [
              IconButton(
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _searchCtrl.clear();
                }),
              ),
              PopupMenuButton<SortKey>(
                icon: const Icon(Icons.sort),
                tooltip: 'Ordenar',
                onSelected: (k) => setState(() {
                  if (k == _sort) {
                    _ascending = !_ascending;
                  } else {
                    _sort = k;
                    _ascending = true;
                  }
                }),
                itemBuilder: (_) => [
                  for (final e in const {
                    SortKey.name: 'Nombre',
                    SortKey.dr: 'Rango dinámico',
                    SortKey.lufs: 'LUFS',
                    SortKey.cutoff: 'Corte espectral',
                  }.entries)
                    PopupMenuItem(
                      value: e.key,
                      child: Row(
                        children: [
                          Expanded(child: Text(e.value)),
                          if (e.key == _sort)
                            Icon(
                              _ascending
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              size: 16,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'csv') _exportCsv();
                  if (v == 'compare') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ComparePage(
                          controller: _c,
                          settings: widget.settings,
                        ),
                      ),
                    );
                  }
                  if (v == 'duplicates') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DuplicatesPage(
                          controller: _c,
                          settings: widget.settings,
                        ),
                      ),
                    );
                  }
                  if (v == 'settings') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SettingsPage(
                          controller: _c,
                          settings: widget.settings,
                        ),
                      ),
                    );
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'compare',
                    child: Text('Comparar canciones'),
                  ),
                  PopupMenuItem(
                    value: 'duplicates',
                    child: Text('Buscar duplicados'),
                  ),
                  PopupMenuItem(value: 'csv', child: Text('Exportar CSV')),
                  PopupMenuItem(value: 'settings', child: Text('Ajustes')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _showAddSheet,
            icon: const Icon(Icons.add),
            label: const Text('Analizar'),
          ),
          body: empty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/icon/logo.png', width: 96),
                        const SizedBox(height: 24),
                        const Text(
                          'Elige una carpeta o canciones para ver su rango dinámico, '
                          'LUFS, pico real, corte espectral y espectrograma.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (_c.scanning)
                      const LinearProgressIndicator(minHeight: 2),
                    if (_c.running) _ProgressCard(controller: _c),
                    if (summary.analyzed > 0) _SummaryCard(summary: summary),
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final e in const {
                            LibFilter.all: 'Todas',
                            LibFilter.suspicious: 'Sospechosas',
                            LibFilter.compressed: 'Comprimidas (DR < 8)',
                          }.entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(e.value),
                                selected: _filter == e.key,
                                onSelected: (_) =>
                                    setState(() => _filter = e.key),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: items.isEmpty
                          ? Center(
                              child: Text(
                                'Nada con ese filtro',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                              itemCount: items.length,
                              itemBuilder: (context, i) => _ItemTile(
                                item: items[i],
                                onTap: () => _open(items[i]),
                              ),
                            ),
                    ),
                  ],
                ),
          ),
        );
      },
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.controller});
  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = controller;
    final total = c.runTotal <= 0 ? 1 : c.runTotal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: GlassCard(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: cs.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Analizadas ${c.runDone} de ${c.runTotal}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(onPressed: c.stop, child: const Text('Detener')),
                ],
              ),
              Text(
                c.currentName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: LinearProgressIndicator(value: c.runDone / total),
              ),
              const SizedBox(height: 4),
              Text(
                c.etaSeconds == null
                    ? 'Puedes salir de la app: sigue analizando en segundo plano.'
                    : 'Quedan ${formatEta(c.etaSeconds!)} · puedes salir de la app, '
                          'sigue en segundo plano.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final LibrarySummary summary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget stat(String label, String value) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: GlassCard(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: cs.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              stat('Analizadas', '${summary.analyzed}'),
              stat('DR promedio', summary.avgDr?.toStringAsFixed(1) ?? '—'),
              stat('LUFS promedio', summary.avgLufs?.toStringAsFixed(1) ?? '—'),
              stat('Sospechosas', '${summary.suspicious}'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Insignia con el rango dinamico: rojo (<8), ambar (<12) o verde.
class _DrBadge extends StatelessWidget {
  const _DrBadge({required this.dr});
  final double dr;

  @override
  Widget build(BuildContext context) {
    final c = dr < 8
        ? const Color(0xFFFF5252)
        : dr < 12
        ? const Color(0xFFFFB300)
        : const Color(0xFF4CAF50);
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dr.toStringAsFixed(1),
            style: TextStyle(color: c, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          Text('DR', style: TextStyle(color: c, fontSize: 9)),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onTap});
  final Item item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = item.data;
    String subtitle;
    String? warning;
    Widget? trailing;

    switch (item.state) {
      case ItemState.waiting:
        subtitle = 'En cola';
      case ItemState.running:
        subtitle = 'Analizando…';
        trailing = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case ItemState.error:
        subtitle = '${item.error ?? 'Error'} · toca para reintentar';
        trailing = Icon(Icons.refresh, color: cs.error);
      case ItemState.done:
        subtitle = _summaryLine(d!);
        warning = suspicionOf(d);
        trailing = Icon(Icons.chevron_right, color: cs.onSurfaceVariant);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                if (item.state == ItemState.done && d != null) ...[
                  _DrBadge(dr: d.dynamicRange),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      if (warning != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 14,
                              color: cs.error,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                warning,
                                style: TextStyle(color: cs.error, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _summaryLine(AudioAnalysisData d) {
    final parts = <String>[
      d.codec,
      '${(d.sampleRate / 1000).toStringAsFixed(1)} kHz',
      d.bitDepth,
      'DR ${d.dynamicRange.toStringAsFixed(1)}',
      if (d.integratedLufs != null)
        '${d.integratedLufs!.toStringAsFixed(1)} LUFS',
      'corte ${formatAudioAnalysisSpectralCutoff(d.spectralCutoffHz, notDetectedLabel: 'no detectado')}',
    ];
    return parts.join(' · ');
  }
}
