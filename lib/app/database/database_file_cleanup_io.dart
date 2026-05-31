import 'dart:io';

Future<void> deleteDefaultIsarFiles(String directory) async {
  final dir = Directory(directory);
  if (!await dir.exists()) return;

  await for (final entity in dir.list()) {
    final name = entity.uri.pathSegments.last;
    if (!name.startsWith('default.isar')) continue;
    try {
      await entity.delete();
    } catch (_) {
      // If a sidecar file cannot be deleted, the second open will surface it.
    }
  }
}
