import 'package:flutter/material.dart';

import 'audio_analysis_models.dart';
import 'compare_page.dart';
import 'detail_page.dart';
import 'duplicates.dart';
import 'format.dart';
import 'library.dart';
import 'settings.dart';

class DuplicatesPage extends StatefulWidget {
  const DuplicatesPage({
    super.key,
    required this.controller,
    required this.settings,
  });

  final LibraryController controller;
  final AppSettings settings;

  @override
  State<DuplicatesPage> createState() => _DuplicatesPageState();
}

class _DuplicatesPageState extends State<DuplicatesPage> {
  late final List<DuplicateGroup> _groups = findDuplicates(
    widget.controller.analyzedItems,
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final exact = _groups.where((g) => g.exact).toList();
    final extraExact = exact.fold<int>(0, (s, g) => s + g.extraBytes);
    final files = _groups.fold<int>(0, (s, g) => s + g.items.length);

    return Scaffold(
      appBar: AppBar(title: const Text('Duplicados')),
      body: _groups.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  widget.controller.analyzedItems.length < 2
                      ? 'Analiza primero una carpeta para buscar duplicados.'
                      : 'No encontré canciones repetidas en lo que has analizado.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: cs.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_groups.length} grupos · $files archivos',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (exact.isNotEmpty)
                          Text(
                            'Copias idénticas: ${exact.length} grupos. '
                            'Quitando las sobrantes liberarías ${formatBytes(extraExact)}.',
                            style: const TextStyle(fontSize: 13),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          'La búsqueda usa solo los números del análisis (duración y '
                          'niveles), no compara el audio completo. Los "probables" '
                          'pueden ser falsos: revísalos con Comparar antes de borrar. '
                          'La app no borra nada.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final g in _groups) ...[
                  _GroupCard(
                    group: g,
                    onOpen: (item) => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DetailPage(
                          item: item,
                          controller: widget.controller,
                          settings: widget.settings,
                        ),
                      ),
                    ),
                    onCompare: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ComparePage(
                          controller: widget.controller,
                          settings: widget.settings,
                          a: g.items[0],
                          b: g.items[1],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.onOpen,
    required this.onCompare,
  });

  final DuplicateGroup group;
  final void Function(Item) onOpen;
  final VoidCallback onCompare;

  static String _folder(String path) {
    final i = path.lastIndexOf('/');
    return i <= 0 ? '' : path.substring(0, i);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: group.exact
                        ? cs.primaryContainer
                        : cs.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    group.exact ? 'Idénticos' : 'Probables',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: group.exact
                          ? cs.onPrimaryContainer
                          : cs.onTertiaryContainer,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(onPressed: onCompare, child: const Text('Comparar')),
              ],
            ),
            for (var i = 0; i < group.items.length; i++)
              _Row(
                item: group.items[i],
                suggested: i == 0,
                folder: _folder(group.items[i].path),
                onTap: () => onOpen(group.items[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.suggested,
    required this.folder,
    required this.onTap,
  });

  final Item item;
  final bool suggested;
  final String folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final AudioAnalysisData d = item.data!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (suggested)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'Mayor calidad',
                      style: TextStyle(
                        color: cs.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${d.codec} · ${(d.sampleRate / 1000).toStringAsFixed(1)} kHz · '
              '${d.bitDepth} · ${formatBytes(d.fileSize)} · '
              'DR ${d.dynamicRange.toStringAsFixed(1)}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            Text(
              folder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
