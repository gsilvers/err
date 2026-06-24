import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The directory Err saves user-visible data into.
///
/// On Android this is the app's external files dir (`Android/data/<pkg>/files`)
/// so recorded GPX/CSV files are reachable over USB and by file managers;
/// elsewhere it falls back to the app documents directory. Centralised here so
/// every writer/reader resolves the same place.
Future<Directory> appStorageDirectory() async {
  final external = Platform.isAndroid
      ? await getExternalStorageDirectory()
      : null;
  return external ?? await getApplicationDocumentsDirectory();
}
