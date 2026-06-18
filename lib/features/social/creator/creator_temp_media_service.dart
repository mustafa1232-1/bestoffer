import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class CreatorTempMediaService {
  /// Optional root override for tests so the service can run without the
  /// path_provider plugin. Production code leaves this null.
  final Directory? overrideRoot;

  const CreatorTempMediaService({this.overrideRoot});

  Future<Directory> ensureDirectory() async {
    final base = overrideRoot ?? await getTemporaryDirectory();
    final creatorDir = Directory(path.join(base.path, 'maslaki_creator'));
    if (!await creatorDir.exists()) {
      await creatorDir.create(recursive: true);
    }
    return creatorDir;
  }

  Future<String> newFilePath({
    required String prefix,
    required String extension,
  }) async {
    final directory = await ensureDirectory();
    final safeExtension = extension.startsWith('.')
        ? extension.substring(1)
        : extension;
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return path.join(directory.path, '${prefix}_$timestamp.$safeExtension');
  }

  Future<File> cleanupAndCopy(File source, {required String prefix}) async {
    final extension = path.extension(source.path).replaceFirst('.', '');
    final targetPath = await newFilePath(
      prefix: prefix,
      extension: extension.isEmpty ? 'bin' : extension,
    );
    return source.copy(targetPath);
  }

  Future<void> clearAgedFiles({Duration maxAge = const Duration(days: 1)}) async {
    final directory = await ensureDirectory();
    if (!await directory.exists()) return;
    final cutoff = DateTime.now().subtract(maxAge);
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) {
        try {
          await entity.delete();
        } catch (_) {
          // Best effort cleanup only.
        }
      }
    }
  }
}
