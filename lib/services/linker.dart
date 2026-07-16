import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import '../models/plugin.dart';

class LinkerService {
  // Callback logger (to print actions to the GUI console)
  final void Function(String message, String type)? onLog;

  LinkerService({this.onLog});

  void log(String msg, String type) {
    if (onLog != null) {
      onLog!(msg, type);
    } else {
      print('[$type] $msg');
    }
  }

  // Helper method to safely copy files/directories
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (var entity in source.list(recursive: false)) {
      if (entity is Directory) {
        var newDirectory = Directory(p.join(destination.absolute.path, p.basename(entity.path)));
        await _copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        await entity.copy(p.join(destination.absolute.path, p.basename(entity.path)));
      }
    }
  }

  Future<void> _copyEntity(String src, String dest) async {
    if (Directory(src).existsSync()) {
      await _copyDirectory(Directory(src), Directory(dest));
    } else if (File(src).existsSync()) {
      await File(src).copy(dest);
    }
  }

  // Delete files/directories, bypassing potential locks or system hurdles
  Future<void> _deleteEntity(String path) async {
    if (Directory(path).existsSync()) {
      await Directory(path).delete(recursive: true);
    } else if (File(path).existsSync()) {
      await File(path).delete();
    }
  }

  // Create safe cross-platform symbolic link, hard link or junction
  Future<void> createSafeLink(String src, String dest, {String strategy = 'symlink'}) async {
    final srcPath = p.absolute(src);
    final destPath = p.absolute(dest);

    if (!Directory(destPath).existsSync() && !File(destPath).existsSync()) {
      throw FileNotFoundError('Destination path does not exist: $destPath');
    }

    // Clean up existing source path if it already exists
    if (Directory(srcPath).existsSync() || File(srcPath).existsSync() || FileSystemEntity.isLinkSync(srcPath) || (Platform.isWindows && await _isWindowsJunction(srcPath))) {
      log('Cleaning up existing path at link site: $srcPath', 'info');
      if (FileSystemEntity.isLinkSync(srcPath)) {
        await Link(srcPath).delete();
      } else if (Platform.isWindows && await _isWindowsJunction(srcPath)) {
        // Remove Directory Junction via rmdir
        await Process.run('cmd', ['/c', 'rmdir', srcPath]);
      } else {
        // Back up existing directory or file
        final backupPath = '$srcPath.bak';
        if (Directory(backupPath).existsSync() || File(backupPath).existsSync()) {
          await _deleteEntity(backupPath);
        }
        await _copyEntity(srcPath, backupPath);
        await _deleteEntity(srcPath);
      }
    }

    // Ensure parent folder of link exists
    await Directory(p.dirname(srcPath)).create(recursive: true);

    bool isDir = FileSystemEntity.isDirectorySync(destPath);

    if (Platform.isWindows) {
      if (strategy == 'hardlink' && !isDir) {
        try {
          // Hardlink using fs link
          await File(destPath).link(srcPath);
          return;
        } catch (_) {}
      }

      // Try Symbolic Link (requires developer mode or administrator)
      try {
        await Link(srcPath).create(destPath);
      } catch (_) {
        // Fallback for standard Windows Users (bypasses UAC!)
        if (isDir) {
          log('Symlink creation blocked. Creating Directory Junction instead...', 'warning');
          // Junction: cmd /c mklink /j "src" "dest"
          var res = await Process.run('cmd', ['/c', 'mklink', '/j', srcPath, destPath]);
          if (res.exitCode != 0) {
            throw OSError(res.stderr.toString());
          }
        } else {
          log('Symlink creation blocked. Creating Hardlink instead...', 'warning');
          // File Hardlink: fsutil or mklink /h
          var res = await Process.run('cmd', ['/c', 'mklink', '/h', srcPath, destPath]);
          if (res.exitCode != 0) {
            // Final fallback: copy file
            await File(destPath).copy(srcPath);
          }
        }
      }
    } else {
      // macOS or Linux
      if (strategy == 'hardlink' && !isDir) {
        await File(destPath).link(srcPath);
      } else {
        await Link(srcPath).create(destPath);
      }
    }
  }

  // Registry utilities
  Future<bool> exportRegistry(String regKey, String outputFile, {String? prefix}) async {
    if (Platform.isWindows) {
      // reg export HKCU\Software\Vendor output.reg /y
      var res = await Process.run('reg', ['export', regKey, outputFile, '/y']);
      return res.exitCode == 0;
    } else {
      if (prefix == null || !Directory(prefix).existsSync()) return false;
      // wine regedit /e output.reg Key
      var res = await Process.run(
        'wine',
        ['regedit', '/e', outputFile, regKey],
        environment: {'WINEPREFIX': prefix},
      );
      return res.exitCode == 0;
    }
  }

  Future<bool> importRegistry(String regFile, {String? prefix}) async {
    if (!File(regFile).existsSync()) return false;

    if (Platform.isWindows) {
      // reg import output.reg
      var res = await Process.run('reg', ['import', regFile]);
      return res.exitCode == 0;
    } else {
      if (prefix == null || !Directory(prefix).existsSync()) return false;
      // wine regedit file.reg
      var res = await Process.run(
        'wine',
        ['regedit', regFile],
        environment: {'WINEPREFIX': prefix},
      );
      return res.exitCode == 0;
    }
  }

  // Relocate plugin files and save json manifest profile
  Future<ManifestModel> packagePlugin({
    required String name,
    required String format,
    required String type,
    required String mainPath,
    required List<String> resourcePaths,
    required String targetDir,
    String strategy = 'symlink',
    List<String>? registryKeys,
    String? winePrefix,
  }) async {
    final targetPath = p.absolute(targetDir);
    await Directory(targetPath).create(recursive: true);

    final List<ManifestLink> links = [];
    final List<ManifestRegistry> registry = [];

    // 1. Move main binary/bundle
    final mainName = p.basename(mainPath);
    final portableBinDir = p.join(targetPath, 'binaries');
    await Directory(portableBinDir).create(recursive: true);
    final portableMainPath = p.join(portableBinDir, mainName);

    log('Relocating plugin binary to portable library...', 'info');
    await _copyEntity(mainPath, portableMainPath);
    await _deleteEntity(mainPath);

    links.add(ManifestLink(
      src: mainPath,
      dest: p.join('binaries', mainName),
      isDir: FileSystemEntity.isDirectorySync(portableMainPath),
    ));

    // 2. Relocate resources
    for (int i = 0; i < resourcePaths.length; i++) {
      final resPath = resourcePaths[i];
      if (!Directory(resPath).existsSync() && !File(resPath).existsSync()) continue;

      final resName = p.basename(resPath);
      final destSubdir = 'resource_${i}_$resName';
      final portableResPath = p.join(targetPath, destSubdir);

      log('Relocating resource configurations: $resName', 'info');
      await _copyEntity(resPath, portableResPath);
      await _deleteEntity(resPath);

      links.add(ManifestLink(
        src: resPath,
        dest: destSubdir,
        isDir: FileSystemEntity.isDirectorySync(portableResPath),
      ));
    }

    // 3. Export registry keys
    if (registryKeys != null && registryKeys.isNotEmpty) {
      final portableRegDir = p.join(targetPath, 'registry');
      await Directory(portableRegDir).create(recursive: true);

      for (int i = 0; i < registryKeys.length; i++) {
        final key = registryKeys[i];
        final filename = 'key_$i.reg';
        final outFilePath = p.join(portableRegDir, filename);

        log('Exporting registry configs: $key', 'info');
        if (await exportRegistry(key, outFilePath, prefix: winePrefix)) {
          registry.add(ManifestRegistry(key: key, file: p.join('registry', filename)));
        }
      }
    }

    final manifest = ManifestModel(
      name: name,
      format: format,
      type: type,
      winePrefix: winePrefix,
      strategy: strategy,
      links: links,
      registry: registry,
    );

    // Save manifest
    final manifestPath = p.join(targetPath, 'symlinkr.json');
    final jsonContent = const JsonEncoder.withIndent('    ').convert(manifest.toJson());
    await File(manifestPath).writeAsString(jsonContent);

    log('Manifest configurations saved successfully.', 'success');

    // Create links back to original paths
    await applyProfile(targetPath, strategy: strategy);

    return manifest;
  }

  // Restore links and registry keys from a manifest profile
  Future<ManifestModel> applyProfile(String portableDir, {String? strategy}) async {
    final portablePath = p.absolute(portableDir);
    final manifestPath = p.join(portablePath, 'symlinkr.json');

    if (!File(manifestPath).existsSync()) {
      throw FileNotFoundError('Manifest not found in $portablePath');
    }

    final jsonContent = await File(manifestPath).readAsString();
    final manifest = ManifestModel.fromJson(jsonDecode(jsonContent) as Map<String, dynamic>);
    final activeStrategy = strategy ?? manifest.strategy;

    // 1. Recreate links
    for (var link in manifest.links) {
      final src = link.src;
      final destAbs = p.join(portablePath, link.dest);
      log('Restoring links: $src -> $destAbs', 'info');
      await createSafeLink(src, destAbs, strategy: activeStrategy);
    }

    // 2. Re-import registry
    for (var reg in manifest.registry) {
      final regFileAbs = p.join(portablePath, reg.file);
      log('Re-importing registry entries: ${reg.key}', 'info');
      await importRegistry(regFileAbs, prefix: manifest.winePrefix);
    }

    return manifest;
  }

  // Remove symlinks/junctions from the host
  Future<int> removeProfile(String portableDir) async {
    final portablePath = p.absolute(portableDir);
    final manifestPath = p.join(portablePath, 'symlinkr.json');

    if (!File(manifestPath).existsSync()) {
      throw FileNotFoundError('Manifest not found in $portablePath');
    }

    final jsonContent = await File(manifestPath).readAsString();
    final manifest = ManifestModel.fromJson(jsonDecode(jsonContent) as Map<String, dynamic>);

    int unlinkedCount = 0;
    for (var link in manifest.links) {
      final src = link.src;
      log('Removing links from host: $src', 'info');
      
      bool removed = false;
      if (FileSystemEntity.isLinkSync(src)) {
        await Link(src).delete();
        removed = true;
      } else if (Platform.isWindows && await _isWindowsJunction(src)) {
        var res = await Process.run('cmd', ['/c', 'rmdir', src]);
        if (res.exitCode == 0) removed = true;
      } else if (File(src).existsSync()) {
        await File(src).delete();
        removed = true;
      }

      if (removed) unlinkedCount++;
    }

    return unlinkedCount;
  }

  // Audit health state of symbolic links/junctions
  Future<Map<String, dynamic>> checkProfileHealth(String portableDir) async {
    final portablePath = p.absolute(portableDir);
    final manifestPath = p.join(portablePath, 'symlinkr.json');

    if (!File(manifestPath).existsSync()) {
      return {'status': 'missing_manifest', 'links': []};
    }

    final jsonContent = await File(manifestPath).readAsString();
    final manifest = ManifestModel.fromJson(jsonDecode(jsonContent) as Map<String, dynamic>);

    final List<Map<String, String>> linksStatus = [];
    bool healthy = true;

    for (var link in manifest.links) {
      final src = link.src;
      final destAbs = p.join(portablePath, link.dest);
      String status = 'healthy';

      final exists = Directory(src).existsSync() || File(src).existsSync();
      final isLink = FileSystemEntity.isLinkSync(src) || (Platform.isWindows && await _isWindowsJunction(src));

      if (!exists && !isLink) {
        status = 'missing';
        healthy = false;
      } else if (!isLink) {
        status = 'mismatched'; // Exist as real folder/files
        healthy = false;
      } else {
        try {
          String resolvedTarget = '';
          if (Platform.isWindows && await _isWindowsJunction(src)) {
            resolvedTarget = await _getWindowsJunctionTarget(src);
          } else {
            resolvedTarget = await Link(src).target();
          }

          if (p.absolute(resolvedTarget) != p.absolute(destAbs)) {
            status = 'mismatched_target';
            healthy = false;
          } else if (!Directory(destAbs).existsSync() && !File(destAbs).existsSync()) {
            status = 'broken';
            healthy = false;
          }
        } catch (_) {
          status = 'unknown_link_target';
          healthy = false;
        }
      }

      linksStatus.add({
        'src': src,
        'dest': destAbs,
        'status': status,
      });
    }

    return {
      'name': manifest.name,
      'format': manifest.format,
      'type': manifest.type,
      'healthy': healthy,
      'links': linksStatus,
    };
  }

  // Windows Junction specific checks
  Future<bool> _isWindowsJunction(String path) async {
    if (!Platform.isWindows || !Directory(path).existsSync()) return false;
    final parent = p.dirname(path);
    final name = p.basename(path);
    try {
      final res = await Process.run('cmd', ['/c', 'dir', '/a', parent]);
      return res.stdout.toString().contains('<JUNCTION>     $name');
    } catch (_) {
      return false;
    }
  }

  Future<String> _getWindowsJunctionTarget(String path) async {
    final parent = p.dirname(path);
    final name = p.basename(path);
    try {
      final res = await Process.run('cmd', ['/c', 'dir', '/a', parent]);
      for (var line in res.stdout.toString().split('\n')) {
        if (line.contains('<JUNCTION>     $name')) {
          final match = RegExp(r'\[(.*?)\]').firstMatch(line);
          if (match != null) {
            return match.group(1)!;
          }
        }
      }
    } catch (_) {}
    return '';
  }
}

class FileNotFoundError implements Exception {
  final String message;
  FileNotFoundError(this.message);
  @override
  String toString() => 'FileNotFoundError: $message';
}
