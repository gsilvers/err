import 'package:flutter/material.dart';

import '../err_theme.dart';
import 'diagnostics.dart';
import 'mini_lisp.dart';
import 'repl_env.dart';

/// Full-screen debug view: a live log stream and a read-only lisp REPL,
/// both over the same [TrackingDiagnostics]. Reached from the bug icon
/// that appears when debug mode is enabled (long-press the app title).
class DebugScreen extends StatefulWidget {
  const DebugScreen({
    super.key,
    required this.diagnostics,
    required this.theme,
  });

  final TrackingDiagnostics diagnostics;
  final ErrTheme theme;

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  static const _categories = ['gps', 'baro', 'elev', 'sys'];
  final Set<String> _enabled = {..._categories};

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: t.screenBackground,
        appBar: AppBar(
          backgroundColor: t.appBarBackground,
          title: Text('Debug', style: TextStyle(color: t.appBarTitle)),
          iconTheme: IconThemeData(color: t.appBarTitle),
          bottom: TabBar(
            labelColor: t.appBarTitle,
            unselectedLabelColor: t.appBarTitle.withAlpha(140),
            indicatorColor: t.startActive,
            tabs: const [Tab(text: 'Log'), Tab(text: 'REPL')],
          ),
        ),
        body: TabBarView(
          children: [
            _buildLogTab(t),
            _ReplView(diagnostics: widget.diagnostics, theme: t),
          ],
        ),
      ),
    );
  }

  // ── Log tab ─────────────────────────────────────────────────────────────

  Widget _buildLogTab(ErrTheme t) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Wrap(
            spacing: 8,
            children: [
              for (final c in _categories)
                FilterChip(
                  label: Text(c),
                  selected: _enabled.contains(c),
                  onSelected: (on) => setState(
                      () => on ? _enabled.add(c) : _enabled.remove(c)),
                  selectedColor: t.toggleSelectedBackground,
                  backgroundColor: t.toggleUnselectedBackground,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: _enabled.contains(c)
                        ? t.toggleSelectedText
                        : t.toggleUnselectedText,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: widget.diagnostics,
            builder: (context, _) {
              final events = widget.diagnostics.events
                  .toList()
                  .reversed // newest first
                  .where((e) => _enabled.contains(e.category))
                  .toList();
              if (events.isEmpty) {
                return Center(
                  child: Text(
                    'No events yet — start tracking.',
                    style: TextStyle(color: t.statLabel),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: events.length,
                itemBuilder: (context, i) => _logRow(events[i], t),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _logRow(DebugEvent e, ErrTheme t) {
    final time = e.time.toIso8601String().substring(11, 19);
    final color = e.message.startsWith('REJECT') ||
            e.message.startsWith('TELEPORT')
        ? t.messageError
        : t.statValue;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: '$time ${e.category.padRight(4)} ',
            style: TextStyle(color: t.statLabel),
          ),
          TextSpan(text: e.message, style: TextStyle(color: color)),
        ]),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}

// ─── REPL tab ────────────────────────────────────────────────────────────────

class _ReplEntry {
  _ReplEntry(this.text, {this.isInput = false, this.isError = false});

  final String text;
  final bool isInput;
  final bool isError;
}

class _ReplView extends StatefulWidget {
  const _ReplView({required this.diagnostics, required this.theme});

  final TrackingDiagnostics diagnostics;
  final ErrTheme theme;

  @override
  State<_ReplView> createState() => _ReplViewState();
}

class _ReplViewState extends State<_ReplView>
    with AutomaticKeepAliveClientMixin {
  late final Interpreter _interp;
  final List<_ReplEntry> _entries = [
    _ReplEntry('Err debug REPL — read-only. (help) lists commands.'),
  ];
  final List<String> _history = [];
  int _historyPos = 0;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  static const _quickKeys = ['(', ')', "'", '(gps)', '(elev)', '(counters)'];

  @override
  bool get wantKeepAlive => true; // session survives tab switches

  @override
  void initState() {
    super.initState();
    _interp = Interpreter();
    installReplEnv(_interp, widget.diagnostics);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final src = text.trim();
    if (src.isEmpty) return;
    setState(() {
      _entries.add(_ReplEntry('err> $src', isInput: true));
      try {
        _entries.add(_ReplEntry(printValue(_interp.run(src))));
      } catch (e) {
        _entries.add(_ReplEntry('error: $e', isError: true));
      }
      _history.add(src);
      _historyPos = _history.length;
      _input.clear();
    });
    _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _recall(int delta) {
    if (_history.isEmpty) return;
    setState(() {
      _historyPos = (_historyPos + delta).clamp(0, _history.length - 1);
      _input.text = _history[_historyPos];
      _input.selection =
          TextSelection.collapsed(offset: _input.text.length);
    });
  }

  void _insert(String text) {
    final sel = _input.selection;
    final at = sel.isValid ? sel.start : _input.text.length;
    _input.text = _input.text.replaceRange(at, at, text);
    _input.selection = TextSelection.collapsed(offset: at + text.length);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = widget.theme;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: _entries.length,
            itemBuilder: (context, i) {
              final e = _entries[i];
              final color = e.isError
                  ? t.messageError
                  : e.isInput
                      ? t.statLabel
                      : t.statValue;
              return GestureDetector(
                // Tapping a previous input recalls it into the field.
                onTap: e.isInput
                    ? () => setState(() {
                          _input.text = e.text.substring(5);
                          _input.selection = TextSelection.collapsed(
                              offset: _input.text.length);
                        })
                    : null,
                child: SelectableText(
                  e.text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: color,
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final k in _quickKeys)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ActionChip(
                    label: Text(k,
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: t.toggleUnselectedText)),
                    backgroundColor: t.toggleUnselectedBackground,
                    onPressed: () => _insert(k),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_upward,
                      size: 18, color: t.statLabel),
                  tooltip: 'Previous command',
                  onPressed: () => _recall(-1),
                ),
                IconButton(
                  icon: Icon(Icons.arrow_downward,
                      size: 18, color: t.statLabel),
                  tooltip: 'Next command',
                  onPressed: () => _recall(1),
                ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    onSubmitted: _submit,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.send,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: t.statValue,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '(help)',
                      hintStyle: TextStyle(color: t.statLabel),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: t.toggleBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: t.startActive),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, size: 20, color: t.startActive),
                  onPressed: () => _submit(_input.text),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
