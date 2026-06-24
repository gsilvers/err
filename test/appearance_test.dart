import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:err/appearance.dart';
import 'package:err/appearance_screen.dart';
import 'package:err/builtin_themes.dart';
import 'package:err/theme_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppearanceSettings', () {
    test('round-trips through JSON', () {
      const s = AppearanceSettings(
        backgroundImage: 'bg.jpg',
        backgroundOpacity: 0.4,
        backgroundFit: BoxFit.contain,
      );
      final restored = AppearanceSettings.fromJson(s.toJson());
      expect(restored.backgroundImage, 'bg.jpg');
      expect(restored.backgroundOpacity, 0.4);
      expect(restored.backgroundFit, BoxFit.contain);
    });

    test('defaults when fields are absent', () {
      final s = AppearanceSettings.fromJson(const {});
      expect(s.backgroundImage, isNull);
      expect(s.backgroundOpacity, 0.25);
      expect(s.backgroundFit, BoxFit.cover);
      expect(s.hasBackground, isFalse);
    });

    test('copyWith can clear the background', () {
      const s = AppearanceSettings(backgroundImage: 'bg.jpg');
      expect(s.copyWith(clearBackground: true).backgroundImage, isNull);
      expect(s.copyWith(backgroundOpacity: 0.9).backgroundImage, 'bg.jpg');
    });

    test('edge images set, clear, and round-trip through JSON', () {
      const base = AppearanceSettings();
      final withTop = base.withEdge(DecorationEdge.top, 'top.png');
      final both = withTop.withEdge(DecorationEdge.left, 'left.png');

      expect(both.edgeImage(DecorationEdge.top), 'top.png');
      expect(both.edgeImage(DecorationEdge.left), 'left.png');
      expect(both.edgeImage(DecorationEdge.right), isNull);

      final restored = AppearanceSettings.fromJson(both.toJson());
      expect(restored.edgeImage(DecorationEdge.top), 'top.png');
      expect(restored.edgeImage(DecorationEdge.left), 'left.png');

      final cleared = both.withoutEdge(DecorationEdge.top);
      expect(cleared.edgeImage(DecorationEdge.top), isNull);
      expect(cleared.edgeImage(DecorationEdge.left), 'left.png');
    });
  });

  group('AppearanceStore', () {
    late Directory dir;
    late AppearanceStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      dir = await Directory.systemTemp.createTemp('err_appearance_');
      store = AppearanceStore(prefs, dir);
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('save then load round-trips', () async {
      const s = AppearanceSettings(
        backgroundImage: 'bg.jpg',
        backgroundOpacity: 0.5,
        backgroundFit: BoxFit.contain,
      );
      await store.save(s);
      final loaded = store.load();
      expect(loaded.backgroundImage, 'bg.jpg');
      expect(loaded.backgroundOpacity, 0.5);
      expect(loaded.backgroundFit, BoxFit.contain);
    });

    test('load returns defaults when nothing is stored', () {
      expect(store.load().hasBackground, isFalse);
    });

    test('importBackground copies the file and keeps its extension', () async {
      final src = File('${dir.path}/source.png');
      await src.writeAsBytes([1, 2, 3]);

      final name = await store.importBackground(src.path);
      expect(name, endsWith('.png'));

      final copied = File('${dir.path}/$name');
      expect(copied.existsSync(), isTrue);
      expect(await copied.readAsBytes(), [1, 2, 3]);
    });

    test('backgroundFile resolves only existing files', () async {
      expect(store.backgroundFile(const AppearanceSettings()), isNull);
      expect(
        store.backgroundFile(
          const AppearanceSettings(backgroundImage: 'missing.jpg'),
        ),
        isNull,
      );

      final src = File('${dir.path}/source.jpg')..writeAsBytesSync([9]);
      final name = await store.importBackground(src.path);
      final file = store.backgroundFile(
        AppearanceSettings(backgroundImage: name),
      );
      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
    });

    test('importImage carries the slot prefix into the filename', () async {
      final src = File('${dir.path}/source.png')..writeAsBytesSync([7]);
      final name = await store.importImage(src.path, prefix: 'edge_left');
      expect(name, startsWith('edge_left_'));
      expect(name, endsWith('.png'));
      expect(store.imageFile(name), isNotNull);
      expect(store.imageFile('nope.png'), isNull);
    });

    test('deleteImage removes the stored file', () async {
      final src = File('${dir.path}/source.jpg')..writeAsBytesSync([9]);
      final name = await store.importBackground(src.path);
      expect(File('${dir.path}/$name').existsSync(), isTrue);

      await store.deleteImage(name);
      expect(File('${dir.path}/$name').existsSync(), isFalse);
    });
  });

  testWidgets('AppearanceScreen renders the empty state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // Real file/prefs IO must run outside the fake-async test zone, or these
    // futures never complete and the test hangs.
    late AppearanceStore store;
    late Directory dir;
    await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      dir = await Directory.systemTemp.createTemp('err_appearance_ui_');
      store = AppearanceStore(prefs, dir);
    });
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    // Tall surface so the lazy ListView builds the side-decoration rows too.
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ErrThemeScope(
          theme: builtinThemes.first,
          child: AppearanceScreen(
            store: store,
            settings: const AppearanceSettings(),
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Choose image'), findsOneWidget);
    expect(find.text('No background image'), findsOneWidget);
    // Opacity/Fit controls only appear once an image is set.
    expect(find.text('Opacity'), findsNothing);
    // Side-decoration edge slots are present.
    expect(find.text('SIDE DECORATIONS'), findsOneWidget);
    expect(find.text('Top'), findsOneWidget);
    expect(find.text('Right'), findsOneWidget);
  });
}
