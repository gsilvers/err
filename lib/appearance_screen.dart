import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'appearance.dart';
import 'err_theme.dart';

/// Pick and tune a background image for the tracker screen. Holds a local copy
/// of [AppearanceSettings] for instant feedback and calls [onChanged] (which
/// persists and repaints the tracker) on every edit.
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({
    super.key,
    required this.theme,
    required this.store,
    required this.settings,
    required this.onChanged,
  });

  final ErrTheme theme;
  final AppearanceStore store;
  final AppearanceSettings settings;
  final ValueChanged<AppearanceSettings> onChanged;

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  late AppearanceSettings _settings = widget.settings;

  void _update(AppearanceSettings next) {
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final previous = _settings.backgroundImage;
    final name = await widget.store.importBackground(picked.path);
    if (previous != null && previous != name) {
      await widget.store.deleteImage(previous);
    }
    _update(_settings.copyWith(backgroundImage: name));
  }

  Future<void> _removeImage() async {
    final previous = _settings.backgroundImage;
    _update(_settings.copyWith(clearBackground: true));
    await widget.store.deleteImage(previous);
  }

  Future<void> _pickEdge(DecorationEdge edge) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final previous = _settings.edgeImage(edge);
    final name = await widget.store.importImage(
      picked.path,
      prefix: 'edge_${edge.name}',
    );
    if (previous != null && previous != name) {
      await widget.store.deleteImage(previous);
    }
    _update(_settings.withEdge(edge, name));
  }

  Future<void> _removeEdge(DecorationEdge edge) async {
    final previous = _settings.edgeImage(edge);
    _update(_settings.withoutEdge(edge));
    await widget.store.deleteImage(previous);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final file = widget.store.backgroundFile(_settings);

    return Scaffold(
      backgroundColor: t.screenBackground,
      appBar: AppBar(
        backgroundColor: t.appBarBackground,
        iconTheme: IconThemeData(color: t.appBarTitle),
        title: Text('Appearance', style: TextStyle(color: t.appBarTitle)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              'BACKGROUND IMAGE',
              style: TextStyle(
                color: t.statLabel,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Text(
            'Put a faint photo behind the stats — a pet, a view, anything. '
            'Keep the opacity low so the numbers stay readable.',
            style: TextStyle(color: t.statLabel, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          // Preview over the theme background, at the chosen opacity.
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: t.screenBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.toggleBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: file == null
                ? Center(
                    child: Text(
                      'No background image',
                      style: TextStyle(color: t.statLabel),
                    ),
                  )
                : Opacity(
                    opacity: _settings.backgroundOpacity,
                    child: Image.file(
                      file,
                      width: double.infinity,
                      height: double.infinity,
                      fit: _settings.backgroundFit,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _pickImage,
                  style: FilledButton.styleFrom(
                    backgroundColor: t.startActive,
                    foregroundColor: t.startForeground,
                  ),
                  icon: const Icon(Icons.image_outlined),
                  label: Text(file == null ? 'Choose image' : 'Replace'),
                ),
              ),
              if (_settings.hasBackground) ...[
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _removeImage,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: t.messageError,
                    side: BorderSide(color: t.toggleBorder),
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
              ],
            ],
          ),
          if (_settings.hasBackground) ...[
            const SizedBox(height: 16),
            Text('Opacity', style: TextStyle(color: t.statValue)),
            Slider(
              value: _settings.backgroundOpacity,
              min: 0.05,
              max: 1.0,
              divisions: 19,
              label: '${(_settings.backgroundOpacity * 100).round()}%',
              activeColor: t.startActive,
              onChanged: (v) =>
                  _update(_settings.copyWith(backgroundOpacity: v)),
            ),
            const SizedBox(height: 8),
            Text('Fit', style: TextStyle(color: t.statValue)),
            const SizedBox(height: 8),
            SegmentedButton<BoxFit>(
              segments: const [
                ButtonSegment(value: BoxFit.cover, label: Text('Cover')),
                ButtonSegment(value: BoxFit.contain, label: Text('Contain')),
              ],
              selected: {_settings.backgroundFit},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  _update(_settings.copyWith(backgroundFit: s.first)),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? t.toggleSelectedBackground
                      : t.toggleUnselectedBackground,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? t.toggleSelectedText
                      : t.toggleUnselectedText,
                ),
                side: WidgetStateProperty.all(
                  BorderSide(color: t.toggleBorder),
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              'SIDE DECORATIONS',
              style: TextStyle(
                color: t.statLabel,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Text(
            'Frame the screen with an image on any edge — a tree on the left, '
            'a skyline up top.',
            style: TextStyle(color: t.statLabel, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 8),
          _edgeRow(t, DecorationEdge.top, 'Top'),
          _edgeRow(t, DecorationEdge.bottom, 'Bottom'),
          _edgeRow(t, DecorationEdge.left, 'Left'),
          _edgeRow(t, DecorationEdge.right, 'Right'),
        ],
      ),
    );
  }

  Widget _edgeRow(ErrTheme t, DecorationEdge edge, String label) {
    final file = widget.store.imageFile(_settings.edgeImage(edge));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: t.screenBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.toggleBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: file == null
                ? Icon(_edgeIcon(edge), color: t.statLabel, size: 20)
                : Image.file(file, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: TextStyle(color: t.statValue)),
          ),
          TextButton(
            onPressed: () => _pickEdge(edge),
            child: Text(
              file == null ? 'Choose' : 'Replace',
              style: TextStyle(color: t.startActive),
            ),
          ),
          if (_settings.edgeImage(edge) != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: t.messageError,
              tooltip: 'Remove',
              onPressed: () => _removeEdge(edge),
            ),
        ],
      ),
    );
  }

  IconData _edgeIcon(DecorationEdge edge) => switch (edge) {
    DecorationEdge.top => Icons.border_top,
    DecorationEdge.bottom => Icons.border_bottom,
    DecorationEdge.left => Icons.border_left,
    DecorationEdge.right => Icons.border_right,
  };
}
