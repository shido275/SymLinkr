import 'dart:io';
import 'package:path/path.dart' as p;

class PluginModel {
  final String name;
  final String format;
  final String path;
  final String type; // native or wine
  final String? prefix; // Wine prefix path if wine
  final int size;

  PluginModel({
    required this.name,
    required this.format,
    required this.path,
    required this.type,
    this.prefix,
    required this.size,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'format': format,
        'path': path,
        'type': type,
        'prefix': prefix,
        'size': size,
      };

  factory PluginModel.fromJson(Map<String, dynamic> json) {
    return PluginModel(
      name: json['name'] as String,
      format: json['format'] as String,
      path: json['path'] as String,
      type: json['type'] as String,
      prefix: json['prefix'] as String?,
      size: json['size'] as int? ?? 0,
    );
  }
}

class ManifestModel {
  final String name;
  final String format;
  final String type;
  final String? winePrefix;
  final String strategy;
  final List<ManifestLink> links;
  final List<ManifestRegistry> registry;

  ManifestModel({
    required this.name,
    required this.format,
    required this.type,
    this.winePrefix,
    required this.strategy,
    required this.links,
    required this.registry,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'format': format,
        'type': type,
        'wine_prefix': winePrefix,
        'strategy': strategy,
        'links': links.map((l) => l.toJson()).toList(),
        'registry': registry.map((r) => r.toJson()).toList(),
      };

  factory ManifestModel.fromJson(Map<String, dynamic> json) {
    var linksList = json['links'] as List? ?? [];
    var regList = json['registry'] as List? ?? [];
    return ManifestModel(
      name: json['name'] as String,
      format: json['format'] as String,
      type: json['type'] as String,
      winePrefix: json['wine_prefix'] as String?,
      strategy: json['strategy'] as String? ?? 'symlink',
      links: linksList.map((l) => ManifestLink.fromJson(l as Map<String, dynamic>)).toList(),
      registry: regList.map((r) => ManifestRegistry.fromJson(r as Map<String, dynamic>)).toList(),
    );
  }
}

class ManifestLink {
  final String src;
  final String dest;
  final bool isDir;

  ManifestLink({
    required this.src,
    required this.dest,
    required this.isDir,
  });

  Map<String, dynamic> toJson() => {
        'src': src,
        'dest': dest,
        'is_dir': isDir,
      };

  factory ManifestLink.fromJson(Map<String, dynamic> json) {
    return ManifestLink(
      src: json['src'] as String,
      dest: json['dest'] as String,
      isDir: json['is_dir'] as bool? ?? false,
    );
  }
}

class ManifestRegistry {
  final String key;
  final String file;

  ManifestRegistry({
    required this.key,
    required this.file,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'file': file,
      };

  factory ManifestRegistry.fromJson(Map<String, dynamic> json) {
    return ManifestRegistry(
      key: json['key'] as String,
      file: json['file'] as String,
    );
  }
}
