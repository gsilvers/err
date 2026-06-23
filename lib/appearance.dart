import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  /// Filename (not path) of the background image inside the decorations dir,
  /// or null for no background.
  final String? backgroundImage;

  /// 0–1; how strongly the image shows over the theme background.
  final double backgroundOpacity;

  final BoxFit backgroundFit;

  bool get hasBackground => backgroundImage != null;

  AppearanceSettings copyWith({
    String? backgroundImage,
    bool clearBackground = false,
    double? backgroundOpacity,
    BoxFit? backgroundFit,
  }) => AppearanceSettings(
    backgroundImage: clearBackground
        ? null
        : (backgroundImage ?? this.backgroundImage),
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    backgroundFit: backgroundFit ?? this.backgroundFit,
  );

  Map<String, dynamic> toJson() => {
    'backgroundImage': backgroundImage,
    'backgroundOpacity': backgroundOpacity,
    'backgroundFit': backgroundFit == BoxFit.contain ? 'contain' : 'cover',
  };

  factory AppearanceSettings.fromJson(Map<String, dynamic> j) =>
      AppearanceSettings(
        backgroundImage: j['backgroundImage'] as String?,
        backgroundOpacity: (j['backgroundOpacity'] as num?)?.toDouble() ?? 0.25,
        backgroundFit: j['backgroundFit'] == 'contain'
            ? BoxFit.contain
            : BoxFit.cover,
      );
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

  /// Resolve the background image to a [File], or null if unset or missing.
  File? backgroundFile(AppearanceSettings s) {
    final name = s.backgroundImage;
    if (name == null) return null;
    final f = File('${decorationsDir.path}/$name');
    return f.existsSync() ? f : null;
  }

  /// Copy a picked image into the decorations dir under a fresh name and
  /// return that filename.
  Future<String> importBackground(String sourcePath) async {
    final dot = sourcePath.lastIndexOf('.');
    final ext = dot >= 0 ? sourcePath.substring(dot + 1) : 'jpg';
    final name = 'bg_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File(sourcePath).copy('${decorationsDir.path}/$name');
    return name;
  }

  /// Delete a stored decoration file by name (no-op if absent).
  Future<void> deleteImage(String? name) async {
    if (name == null) return;
    final f = File('${decorationsDir.path}/$name');
    if (await f.exists()) await f.delete();
  }
}
