import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'builtin_themes.dart';
import 'err_theme.dart';

class CustomThemeEditorScreen extends StatefulWidget {
  const CustomThemeEditorScreen({
    super.key,
    required this.onSave,
    this.editing,
    this.baseTheme,
  });

  final void Function(ErrTheme) onSave;
  final ErrTheme? editing;
  final ErrTheme? baseTheme;

  @override
  State<CustomThemeEditorScreen> createState() =>
      _CustomThemeEditorScreenState();
}

class _CustomThemeEditorScreenState extends State<CustomThemeEditorScreen> {
  late TextEditingController _nameCtrl;
  late ErrTheme _draft;

  @override
  void initState() {
    super.initState();
    final base = widget.editing ?? widget.baseTheme ?? builtinThemes.first;
    _draft = base.copyWith(
      id: widget.editing?.id ??
          'custom_${DateTime.now().millisecondsSinceEpoch}',
    );
    _nameCtrl = TextEditingController(
      text: widget.editing != null ? base.name : '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _pickColor(String slotKey) async {
    Color current = errThemeGetSlot(_draft, slotKey);
    Color picked = current;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _draft.screenBackground,
        title: Text(
          errThemeSlots.firstWhere((s) => s.$1 == slotKey).$2,
          style: TextStyle(color: _draft.statValue, fontSize: 15),
        ),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: current,
            onColorChanged: (c) => picked = c,
            enableAlpha: false,
            hexInputBar: true,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: _draft.statLabel)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: _draft.startActive),
            onPressed: () {
              setState(() {
                _draft = errThemeSetSlot(_draft, slotKey, picked);
              });
              Navigator.pop(ctx);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a theme name.')),
      );
      return;
    }
    widget.onSave(_draft.copyWith(name: name));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _draft.screenBackground,
      appBar: AppBar(
        backgroundColor: _draft.appBarBackground,
        iconTheme: IconThemeData(color: _draft.appBarTitle),
        title: Text(
          widget.editing == null ? 'New Theme' : 'Edit Theme',
          style: TextStyle(color: _draft.appBarTitle),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text('Save',
                style: TextStyle(
                    color: _draft.startActive,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Live preview strip
          _PreviewStrip(theme: _draft),
          // Name + dark toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _nameCtrl,
              style: TextStyle(color: _draft.statValue),
              decoration: InputDecoration(
                labelText: 'Theme name',
                labelStyle: TextStyle(color: _draft.statLabel),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: _draft.toggleBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: _draft.startActive),
                ),
              ),
            ),
          ),
          SwitchListTile(
            value: _draft.isDark,
            onChanged: (v) => setState(() => _draft = _draft.copyWith(isDark: v)),
            title:
                Text('Dark theme', style: TextStyle(color: _draft.statValue)),
            activeThumbColor: _draft.startActive,
            activeTrackColor: _draft.startActive.withAlpha(120),
          ),
          const Divider(height: 1),
          // Slot list
          Expanded(
            child: ListView.builder(
              itemCount: errThemeSlots.length,
              itemBuilder: (_, i) {
                final (key, label) = errThemeSlots[i];
                final color = errThemeGetSlot(_draft, key);
                final hex =
                    '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
                return ListTile(
                  tileColor: _draft.screenBackground,
                  leading: GestureDetector(
                    onTap: () => _pickColor(key),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: _draft.toggleBorder, width: 1),
                      ),
                    ),
                  ),
                  title: Text(label,
                      style: TextStyle(color: _draft.statValue, fontSize: 13)),
                  subtitle: Text(hex,
                      style: TextStyle(
                          color: _draft.statLabel,
                          fontSize: 11,
                          fontFamily: 'monospace')),
                  onTap: () => _pickColor(key),
                  trailing:
                      Icon(Icons.chevron_right, color: _draft.toggleBorder),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewStrip extends StatelessWidget {
  const _PreviewStrip({required this.theme});
  final ErrTheme theme;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Container(
      color: t.appBarBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: t.screenBackground,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text('1.2',
                  style: TextStyle(
                      color: t.statValue,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 6,
                  width: 60,
                  decoration: BoxDecoration(
                    color: t.statValue.withAlpha(200),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: t.statLabel.withAlpha(160),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _pill(t.startActive),
          const SizedBox(width: 6),
          _pill(t.stopActive),
        ],
      ),
    );
  }

  Widget _pill(Color c) => Container(
        width: 32,
        height: 18,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(9),
        ),
      );
}
