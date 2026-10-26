import 'package:flutter/material.dart';

import 'audio_analysis_models.dart';
import 'library.dart';

/// Lista con buscador para elegir una cancion ya analizada.
class PickSongPage extends StatefulWidget {
  const PickSongPage({super.key, required this.controller, this.title});

  final LibraryController controller;
  final String? title;

  @override
  State<PickSongPage> createState() => _PickSongPageState();
}

class _PickSongPageState extends State<PickSongPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _search.text.trim().toLowerCase();
    final items = widget.controller.analyzedItems
        .where((i) => q.isEmpty || i.nameLower.contains(q))
        .toList()
      ..sort((a, b) => a.nameLower.compareTo(b.nameLower));

    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'Elegir canción')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar canción',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: cs.surfaceContainer,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      widget.controller.analyzedItems.isEmpty
                          ? 'Primero analiza algunas canciones'
                          : 'Nada con esa búsqueda',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final AudioAnalysisData d = item.data!;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Material(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(20),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            title: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${d.codec} · ${(d.sampleRate / 1000).toStringAsFixed(1)} kHz · '
                              '${d.bitDepth} · DR ${d.dynamicRange.toStringAsFixed(1)}',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            onTap: () => Navigator.of(context).pop(item),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
