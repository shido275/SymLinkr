import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/plugin.dart';

class ScannerService {
  // Standard Native Linux plugin paths
  static final Map<String, List<String>> linuxPaths = {
    'VST2': [
      '${Platform.environment['HOME']}/.vst',
      '/usr/lib/vst',
      '/usr/local/lib/vst',
    ],
    'VST3': [
      '${Platform.environment['HOME']}/.vst3',
      '/usr/lib/vst3',
      '/usr/local/lib/vst3',
    ],
    'CLAP': [
      '${Platform.environment['HOME']}/.clap',
      '/usr/lib/clap',
      '/usr/local/lib/clap',
    ],
  };

  // Standard Native Windows plugin paths
  static final Map<String, List<String>> windowsPaths = {
    'VST2': [
      'C:\\Program Files\\VSTPlugins',
      'C:\\Program Files\\Steinberg\\VSTPlugins',
      'C:\\Program Files (x86)\\VSTPlugins',
      'C:\\Program Files (x86)\\Steinberg\\VSTPlugins',
    ],
    'VST3': [
      'C:\\Program Files\\Common Files\\VST3',
      'C:\\Program Files (x86)\\Common Files\\VST3',
    ],
    'CLAP': [
      'C:\\Program Files\\Common Files\\CLAP',
      'C:\\Program Files (x86)\\Common Files\\CLAP',
    ],
    'AAX': [
      'C:\\Program Files\\Common Files\\Avid\\Audio\\Plug-Ins',
      'C:\\Program Files (x86)\\Common Files\\Avid\\Audio\\Plug-Ins',
    ],
  };

  // Standard Native macOS plugin paths
  static final Map<String, List<String>> macosPaths = {
    'VST2': [
      '/Library/Audio/Plug-Ins/VST',
      '${Platform.environment['HOME']}/Library/Audio/Plug-Ins/VST',
    ],
    'VST3': [
      '/Library/Audio/Plug-Ins/VST3',
      '${Platform.environment['HOME']}/Library/Audio/Plug-Ins/VST3',
    ],
    'CLAP': [
      '/Library/Audio/Plug-Ins/CLAP',
      '${Platform.environment['HOME']}/Library/Audio/Plug-Ins/CLAP',
    ],
    'AAX': [
      '/Library/Application Support/Avid/Audio/Plug-Ins',
    ],
  };

  // Standard relative paths within a Wine prefix (for Linux Wine scanner)
  static final Map<String, List<String>> wineRelativePaths = {
    'VST2': [
      'drive_c/Program Files/VSTPlugins',
      'drive_c/Program Files/Steinberg/VSTPlugins',
      'drive_c/Program Files (x86)/VSTPlugins',
    ],
    'WINE_VST3': [
      'drive_c/Program Files/Common Files/VST3',
      'drive_c/Program Files (x86)/Common Files/VST3',
    ],
    'WINE_CLAP': [
      'drive_c/Program Files/Common Files/CLAP',
      'drive_c/Program Files (x86)/Common Files/CLAP',
    ],
    'WINE_AAX': [
      'drive_c/Program Files/Common Files/Avid/Audio/Plug-Ins',
      'drive_c/Program Files (x86)/Common Files/Avid/Audio/Plug-Ins',
    ],
  };

  // Common Windows resource folders to look for presets/licenses
  static final List<String> windowsResourceDirs = [
    'C:\\ProgramData',
    'C:\\Users\\Public\\Documents',
    'APPDATA\\Roaming', // Resolved dynamically relative to UserProfile
    'APPDATA\\Local',
    'DOCUMENTS',
  ];

  // Common folders within Wine prefix (Linux)
  static final List<String> wineResourceDirs = [
    'drive_c/ProgramData',
    'drive_c/users/Public/Documents',
    'drive_c/users/{user}/AppData/Roaming',
    'drive_c/users/{user}/AppData/Local',
    'drive_c/users/{user}/Documents',
  ];

  static final List<String> linuxResourceDirs = [
    '${Platform.environment['HOME']}/.config',
    '${Platform.environment['HOME']}/.local/share',
    '${Platform.environment['HOME']}/Documents',
  ];

  // Detect common Wine prefixes on the system (Linux only)
  List<String> getWinePrefixes() {
    if (!Platform.isLinux) return [];

    final List<String> prefixes = [];
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return [];

    // 1. Default Wine prefix
    final defaultPrefix = p.join(home, '.wine');
    if (Directory(defaultPrefix).existsSync()) {
      prefixes.add(defaultPrefix);
    }

    // 2. Bottles
    final bottlesPath = p.join(home, '.var', 'app', 'com.usebottles.bottles', 'data', 'bottles', 'bottles');
    final bottlesDir = Directory(bottlesPath);
    if (bottlesDir.existsSync()) {
      try {
        for (var entity in bottlesDir.listSync()) {
          if (entity is Directory && Directory(p.join(entity.path, 'drive_c')).existsSync()) {
            prefixes.add(entity.path);
          }
        }
      } catch (_) {}
    }

    // 3. Lutris
    final lutrisPath = p.join(home, 'Games');
    final lutrisDir = Directory(lutrisPath);
    if (lutrisDir.existsSync()) {
      try {
        for (var entity in lutrisDir.listSync()) {
          if (entity is Directory && Directory(p.join(entity.path, 'drive_c')).existsSync()) {
            prefixes.add(entity.path);
          }
        }
      } catch (_) {}
    }

    return prefixes.toSet().toList(); // Unique resolved paths
  }

  List<String> findWineUsers(String prefix) {
    final usersPath = p.join(prefix, 'drive_c', 'users');
    final usersDir = Directory(usersPath);
    if (!usersDir.existsSync()) {
      return ['crossover', 'steamuser', 'default'];
    }

    final List<String> users = [];
    try {
      for (var entry in usersDir.listSync()) {
        final name = p.basename(entry.path);
        if (entry is Directory && name != 'Public' && name != 'All Users' && name != 'Default User') {
          users.add(name);
        }
      }
    } catch (_) {}
    return users.isEmpty ? ['crossover'] : users;
  }

  // Scan local plugins installed natively on this system
  List<PluginModel> scanNativePlugins() {
    final List<PluginModel> plugins = [];
    Map<String, List<String>> pathsDict;

    if (Platform.isWindows) {
      pathsDict = windowsPaths;
    } else if (Platform.isMacOS) {
      pathsDict = macosPaths;
    } else if (Platform.isLinux) {
      pathsDict = linuxPaths;
    } else {
      return []; // Unsupported (e.g. iOS standalone scanning not allowed)
    }

    pathsDict.forEach((fmt, paths) {
      for (var path in paths) {
        final dir = Directory(path);
        if (!dir.existsSync()) continue;

        try {
          for (var entry in dir.listSync()) {
            final entryName = p.basename(entry.path);
            final nameLower = entryName.toLowerCase();
            bool isPlugin = false;

            if (fmt == 'VST3' && (nameLower.endsWith('.vst3') || entry is Directory)) {
              isPlugin = true;
            } else if (fmt == 'CLAP' && nameLower.endsWith('.clap')) {
              isPlugin = true;
            } else if (fmt == 'AAX' && (nameLower.endsWith('.aaxplugin') || entry is Directory)) {
              isPlugin = true;
            } else if (fmt == 'VST2' && (nameLower.endsWith('.so') || nameLower.endsWith('.dll') || nameLower.endsWith('.vst'))) {
              isPlugin = true;
            }

            if (isPlugin) {
              int size = 0;
              try {
                size = getDirSize(entry.path);
              } catch (_) {}

              plugins.add(PluginModel(
                name: p.basenameWithoutExtension(entry.path),
                format: fmt,
                path: entry.path,
                type: 'native',
                size: size,
              ));
            }
          }
        } catch (_) {}
      }
    });

    return plugins;
  }

  // Scan plugins inside a specific Wine prefix (Linux/macOS)
  List<PluginModel> scanWinePlugins(String prefix) {
    if (Platform.isWindows) return [];

    final List<PluginModel> plugins = [];
    final prefixDir = Directory(prefix);
    if (!prefixDir.existsSync()) return [];

    wineRelativePaths.forEach((fmt, relPaths) {
      for (var relPath in relPaths) {
        final fullPath = p.join(prefix, relPath);
        final dir = Directory(fullPath);
        if (!dir.existsSync()) continue;

        try {
          for (var entry in dir.listSync()) {
            final entryName = p.basename(entry.path);
            bool isPlugin = false;

            if (entryName.endsWith('.vst3') || entryName.endsWith('.dll') || entryName.endsWith('.clap') || entryName.endsWith('.aaxplugin') || entry is Directory) {
              if (fmt == 'WINE_VST3' && (entryName.endsWith('.vst3') || entry is Directory)) {
                isPlugin = true;
              } else if (fmt == 'WINE_CLAP' && entryName.endsWith('.clap')) {
                isPlugin = true;
              } else if (fmt == 'WINE_AAX' && (entryName.endsWith('.aaxplugin') || entry is Directory)) {
                isPlugin = true;
              } else if (fmt == 'VST2' && entryName.endsWith('.dll')) {
                isPlugin = true;
              }
            }

            if (isPlugin) {
              int size = 0;
              try {
                size = getDirSize(entry.path);
              } catch (_) {}

              plugins.add(PluginModel(
                name: p.basenameWithoutExtension(entry.path),
                format: fmt.replaceFirst('WINE_', ''),
                path: entry.path,
                type: 'wine',
                prefix: prefix,
                size: size,
              ));
            }
          }
        } catch (_) {}
      }
    });

    return plugins;
  }

  int getDirSize(String path) {
    final file = File(path);
    if (file.existsSync()) return file.lengthSync();

    final dir = Directory(path);
    if (!dir.existsSync()) return 0;

    int totalSize = 0;
    try {
      for (var entity in dir.listSync(recursive: true)) {
        if (entity is File) {
          totalSize += entity.lengthSync();
        }
      }
    } catch (_) {}
    return totalSize;
  }

  // Find associated folders & registry keys matching a plugin name
  Future<List<Map<String, String>>> findAssociatedResources(String pluginName, {bool isWine = false, String? prefix}) async {
    final List<Map<String, String>> suggestions = [];
    final nameClean = pluginName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'] ?? '';

      // 1. Traverse directories
      for (var rDir in windowsResourceDirs) {
        String resolvedDir = rDir;
        if (rDir.startsWith('APPDATA\\Roaming')) {
          resolvedDir = p.join(userProfile, 'AppData', 'Roaming');
        } else if (rDir.startsWith('APPDATA\\Local')) {
          resolvedDir = p.join(userProfile, 'AppData', 'Local');
        } else if (rDir.startsWith('DOCUMENTS')) {
          resolvedDir = p.join(userProfile, 'Documents');
        }

        final dir = Directory(resolvedDir);
        if (!dir.existsSync()) continue;

        try {
          for (var entry in dir.listSync()) {
            final entryName = p.basename(entry.path);
            final entryClean = entryName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
            if (entryClean.contains(nameClean) || nameClean.contains(entryClean)) {
              suggestions.add({
                'path': entry.path,
                'description': 'Windows ${p.basename(resolvedDir)} folder matching "$entryName"',
              });
            }
          }
        } catch (_) {}
      }

      // 2. Scan Registry via Command Line reg query (UAC safe!)
      for (var hive in ['HKCU\\Software', 'HKLM\\Software']) {
        try {
          var result = await Process.run('reg', ['query', hive]);
          if (result.exitCode == 0) {
            var output = result.stdout.toString();
            for (var line in output.split('\n')) {
              var trimmed = line.trim();
              if (trimmed.isEmpty) continue;
              var keyName = p.basename(trimmed);
              var keyClean = keyName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
              if (keyClean.contains(nameClean) || nameClean.contains(keyClean)) {
                suggestions.add({
                  'path': trimmed,
                  'description': 'Windows Registry Key Suggestion',
                });
              }
            }
          }
        } catch (_) {}
      }
    } else {
      // Linux or macOS
      if (isWine && prefix != null) {
        final users = findWineUsers(prefix);
        for (var user in users) {
          for (var rDir in wineResourceDirs) {
            final formattedDir = rDir.replaceFirst('{user}', user);
            final fullPath = p.join(prefix, formattedDir);
            final dir = Directory(fullPath);
            if (!dir.existsSync()) continue;

            try {
              for (var entry in dir.listSync()) {
                final entryName = p.basename(entry.path);
                final entryClean = entryName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
                if (entryClean.contains(nameClean) || nameClean.contains(entryClean)) {
                  suggestions.add({
                    'path': entry.path,
                    'description': 'Wine ${rDir.split('/').last} folder matching "$entryName"',
                  });
                }
              }
            } catch (_) {}
          }
        }
      } else {
        // Native Linux/macOS resource suggestions
        for (var rDir in linuxResourceDirs) {
          final dir = Directory(rDir);
          if (!dir.existsSync()) continue;

          try {
            for (var entry in dir.listSync()) {
              final entryName = p.basename(entry.path);
              final entryClean = entryName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
              if (entryClean.contains(nameClean) || nameClean.contains(entryClean)) {
                suggestions.add({
                  'path': entry.path,
                  'description': 'Local ${p.basename(rDir)} folder matching "$entryName"',
                });
              }
            }
          } catch (_) {}
        }
      }
    }

    return suggestions;
  }
}
