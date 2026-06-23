import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The four screen edges that can carry a decorative image.
enum DecorationEdge { top, bottom, left, right }

/// User-chosen screen decorations, kept separate from the colour theme on
/// purpose:
/// themes are colour-only and portable (ported from ef-themes, shareable as
/// JSON), whereas these reference large, device-local image files.
///
/// Only the image *filename* is persisted; the absolute path is resolved
/// against the decorations directory at load time, so it survives the app's
/// sandbox path changing between installs.
class AppearanceSettings {
  const AppearanceSettings({
    this.backgroundImage,
    this.backgroundOpacity = 0.25,
    this.backgroundFit = BoxFit.cover,
    this.edgeImages = const {},
  });

  /// Filename (not path) of the background image inside the decorations dir,
  /// or null for no background.
  final String? backgroundImage;

  /// 0–1; how strongly the image shows over the theme background.
  final double backgroundOpacity;

  final BoxFit backgroundFit;

  /// Optional decorative image filename per screen edge.
  final Map<DecorationEdge, String> edgeImages;

  bool get hasBackground => backgroundImage != null;

  String? edgeImage(DecorationEdge edge) => edgeImages[edge];

  AppearanceSettings copyWith({
    String? backgroundImage,
    bool clearBackground = false,
    double? backgroundOpacity,
    BoxFit? backgroundFit,
    Map<DecorationEdge, String>? edgeImages,
  }) => AppearanceSettings(
    backgroundImage: clearBackground
        ? null
        : (backgroundImage ?? this.backgroundImage),
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    backgroundFit: backgroundFit ?? this.backgroundFit,
    edgeImages: edgeImages ?? this.edgeImages,
  );

  /// Set the image on one edge, leaving the others untouched.
  AppearanceSettings withEdge(DecorationEdge edge, String name) =>
      copyWith(edgeImages: {...edgeImages, edge: name});

  /// Clear the image from one edge.
  AppearanceSettings withoutEdge(DecorationEdge edge) {
    final next = Map<DecorationEdge, String>.from(edgeImages)..remove(edge);
    return copyWith(edgeImages: next);
  }

  Map<String, dynamic> toJson() => {
    'backgroundImage': backgroundImage,
    'backgroundOpacity': backgroundOpacity,
    'backgroundFit': backgroundFit == BoxFit.contain ? 'contain' : 'cover',
    'edgeImages': {for (final e in edgeImages.entries) e.key.name: e.value},
  };

  factory AppearanceSettings.fromJson(Map<String, dynamic> j) =>
      AppearanceSettings(
        backgroundImage: j['backgroundImage'] as String?,
        backgroundOpacity: (j['backgroundOpacity'] as num?)?.toDouble() ?? 0.25,
        backgroundFit: j['backgroundFit'] == 'contain'
            ? BoxFit.contain
            : BoxFit.cover,
        edgeImages: _edgesFromJson(j['edgeImages']),
      );

  static Map<DecorationEdge, String> _edgesFromJson(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <DecorationEdge, String>{};
    for (final edge in DecorationEdge.values) {
      final v = raw[edge.name];
      if (v is String) out[edge] = v;
    }
    return out;
  }
}

/// Persists [AppearanceSettings] and manages the on-disk image files. The
/// image import takes a plain source path (the screen supplies it from the
/// platform picker), so this class itself has no platform-channel
/// dependencies and is unit-testable with a temp directory.
class AppearanceStore {
  AppearanceStore(this._prefs, this.decorationsDir);

  static const _prefsKey = 'appearance';

  final SharedPreferences _prefs;
  final Directory decorationsDir;

  static Future<AppearanceStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/decorations');
    if (!await dir.exists()) await dir.create(recursive: true);
    return AppearanceStore(prefs, dir);
  }

  AppearanceSettings load() {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null) return const AppearanceSettings();
    try {
      return AppearanceSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const AppearanceSettings();
    }
  }

  Future<void> save(AppearanceSettings s) =>
      _prefs.setString(_prefsKey, jsonEncode(s.toJson()));

  /// Resolve a stored filename to a [File], or null if unset or missing.
  File? imageFile(String? name) {
    if (name == null) return null;
    final f = File('${decorationsDir.path}/$name');
    return f.existsSync() ? f : null;
  }

  /// Resolve the background image to a [File], or null if unset or missing.
  File? backgroundFile(AppearanceSettings s) => imageFile(s.backgroundImage);

  /// Copy a picked image into the decorations dir under a fresh name (carrying
  /// [prefix] so the different slots are distinguishable) and return that
  /// filename.
  Future<String> importImage(String sourcePath, {String prefix = 'img'}) async {
    final dot = sourcePath.lastIndexOf('.');
    final ext = dot >= 0 ? sourcePath.substring(dot + 1) : 'jpg';
    final name = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File(sourcePath).copy('${decorationsDir.path}/$name');
    return name;
  }

  Future<String> importBackground(String sourcePath) =>
      importImage(sourcePath, prefix: 'bg');

  /// Delete a stored decoration file by name (no-op if absent).
  Future<void> deleteImage(String? name) async {
    if (name == null) return;
    final f = File('${decorationsDir.path}/$name');
    if (await f.exists()) await f.delete();
  }
}
