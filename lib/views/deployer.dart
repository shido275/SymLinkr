import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../services/linker.dart';

class DeployerView extends StatefulWidget {
  final void Function(String message, String type) logCallback;

  const DeployerView({super.key, required this.logCallback});

  @override
  State<DeployerView> createState() => _DeployerViewState();
}

class _DeployerViewState extends State<DeployerView> {
  late LinkerService _linker;

  final TextEditingController _restoreDirController = TextEditingController();
  final TextEditingController _libraryDirController = TextEditingController();

  Map<String, dynamic>? _manifestInfo;
  bool _loadingManifest = false;

  List<Map<String, dynamic>> _scannedProfiles = [];
  bool _scanningLibrary = false;

  @override
  void initState() {
    super.initState();
    _linker = LinkerService(onLog: widget.logCallback);
  }

  Future<void> _browseRestoreDir() async {
    String? result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        _restoreDirController.text = result;
      });
      _loadManifestInfo(result);
    }
  }

  Future<void> _browseLibraryDir() async {
    String? result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        _libraryDirController.text = result;
      });
    }
  }

  Future<void> _loadManifestInfo(String path) async {
    setState(() {
      _loadingManifest = true;
      _manifestInfo = null;
    });

    try {
      final manifestFile = File(p.join(path, 'symlinkr.json'));
      if (!manifestFile.existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No symlinkr.json found in this directory.')),
        );
        setState(() => _loadingManifest = false);
        return;
      }

      final health = await _linker.checkProfileHealth(path);
      setState(() {
        _manifestInfo = health;
        _loadingManifest = false;
      });
      widget.logCallback('Loaded portable profile: ${health['name']}', 'success');
    } catch (e) {
      setState(() => _loadingManifest = false);
      widget.logCallback('Failed to load profile info: $e', 'error');
    }
  }

  Future<void> _deploySingle() async {
    final path = _restoreDirController.text.trim();
    if (path.isEmpty) return;

    widget.logCallback('Deploying portable plugin: $path', 'info');
    try {
      await _linker.applyProfile(path);
      widget.logCallback('Plugin symlinks deployed successfully!', 'success');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deployment complete. All symlinks recreated.')),
      );
    } catch (e) {
      widget.logCallback('Deployment failed: $e', 'error');
    }
  }

  Future<void> _scanLibrary() async {
    final libPath = _libraryDirController.text.trim();
    if (libPath.isEmpty) return;

    setState(() {
      _scanningLibrary = true;
      _scannedProfiles.clear();
    });

    widget.logCallback('Scanning library folders for SymLinkr packages...', 'info');

    // Run directory listing in background
    await Future.delayed(const Duration(milliseconds: 300));
    try {
      final dir = Directory(libPath);
      if (!dir.existsSync()) {
        setState(() => _scanningLibrary = false);
        return;
      }

      final List<Map<String, dynamic>> profiles = [];
      await for (var entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && p.basename(entity.path) == 'symlinkr.json') {
          final parentDir = p.dirname(entity.path);
          final health = await _linker.checkProfileHealth(parentDir);
          profiles.add({
            'name': health['name'],
            'format': health['format'],
            'type': health['type'],
            'healthy': health['healthy'],
            'path': parentDir,
          });
        }
      }

      setState(() {
        _scannedProfiles = profiles;
        _scanningLibrary = false;
      });
      widget.logCallback('Library scan finished. Found ${profiles.length} profiles.', 'success');
    } catch (e) {
      setState(() => _scanningLibrary = false);
      widget.logCallback('Library scan failed: $e', 'error');
    }
  }

  Future<void> _deployFromLibrary(String path, int index) async {
    widget.logCallback('Deploying profile from library: $path', 'info');
    try {
      await _linker.applyProfile(path);
      widget.logCallback('Linked successfully!', 'success');
      setState(() {
        _scannedProfiles[index]['healthy'] = true;
      });
    } catch (e) {
      widget.logCallback('Deployment failed: $e', 'error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Deploy & Link Restorer',
          style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Deploy portable plugins on a new system or Wine environment in one click.',
          style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF8C8C8C)),
        ),
        const SizedBox(height: 32),

        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Single Restorer
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1118).withOpacity(0.65),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Restore Single Plugin', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Divider(color: Colors.white10, height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _restoreDirController,
                              decoration: const InputDecoration(
                                labelText: 'Portable Plugin Folder',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _browseRestoreDir,
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
                            child: const Text('Browse'),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 24),
                      if (_loadingManifest)
                        const Center(child: CircularProgressIndicator())
                      else if (_manifestInfo != null)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Chip(label: Text(_manifestInfo!['format'])),
                                  const SizedBox(width: 12),
                                  Text(
                                    _manifestInfo!['name'],
                                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text('Shortcuts to recreate:', style: TextStyle(fontWeight: FontWeight.w600, color: const Color(0xFF8C8C8C))),
                              const SizedBox(height: 8),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: (_manifestInfo!['links'] as List).length,
                                  itemBuilder: (context, idx) {
                                    final l = (_manifestInfo!['links'] as List)[idx];
                                    return ListTile(
                                      title: Text(l['src'], style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                                      leading: const Icon(Icons.link, size: 14),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _deploySingle,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(double.infinity, 44)),
                                child: const Text('Deploy & Link'),
                              ),
                            ],
                          ),
                        )
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              
              // Library Restorer
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1118).withOpacity(0.65),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bulk Library Restorer', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Divider(color: Colors.white10, height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _libraryDirController,
                              decoration: const InputDecoration(
                                labelText: 'Library Parent Directory',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _browseLibraryDir,
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
                            child: const Text('Browse'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _scanningLibrary ? null : _scanLibrary,
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9254DE), minimumSize: const Size(double.infinity, 44)),
                        child: _scanningLibrary ? const CircularProgressIndicator() : const Text('Scan Library Folder'),
                      ),
                      
                      const SizedBox(height: 24),
                      Expanded(
                        child: _scannedProfiles.isEmpty
                            ? Center(child: Text('No library scans running.', style: TextStyle(color: const Color(0xFF8C8C8C))))
                            : ListView.builder(
                                itemCount: _scannedProfiles.length,
                                itemBuilder: (context, idx) {
                                  final p = _scannedProfiles[idx];
                                  return ListTile(
                                    title: Text(p['name']),
                                    subtitle: Text(p['format']),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          p['healthy'] ? Icons.check_circle : Icons.warning,
                                          color: p['healthy'] ? Colors.green : Colors.amber,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 12),
                                        ElevatedButton(
                                          onPressed: () => _deployFromLibrary(p['path'], idx),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
                                          child: const Text('Link'),
                                        )
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
