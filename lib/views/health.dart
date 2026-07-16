import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../services/linker.dart';

class HealthView extends StatefulWidget {
  final void Function(String message, String type) logCallback;

  const HealthView({super.key, required this.logCallback});

  @override
  State<HealthView> createState() => _HealthViewState();
}

class _HealthViewState extends State<HealthView> {
  late LinkerService _linker;

  final TextEditingController _libraryPathController = TextEditingController();
  List<Map<String, dynamic>> _brokenLinks = [];
  bool _auditing = false;

  @override
  void initState() {
    super.initState();
    _linker = LinkerService(onLog: widget.logCallback);
  }

  Future<void> _browseLibrary() async {
    String? result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        _libraryPathController.text = result;
      });
    }
  }

  Future<void> _auditLinks() async {
    final path = _libraryPathController.text.trim();
    if (path.isEmpty) return;

    setState(() {
      _brokenLinks.clear();
      _auditing = true;
    });

    widget.logCallback('Auditing folder symbolic links and junctions...', 'info');
    await Future.delayed(const Duration(milliseconds: 350));

    try {
      final dir = Directory(path);
      if (!dir.existsSync()) {
        setState(() => _auditing = false);
        return;
      }

      final List<Map<String, dynamic>> broken = [];
      await for (var entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && p.basename(entity.path) == 'symlinkr.json') {
          final parentDir = p.dirname(entity.path);
          final health = await _linker.checkProfileHealth(parentDir);
          
          final List links = health['links'] as List? ?? [];
          for (var link in links) {
            if (link['status'] != 'healthy') {
              broken.add({
                'pluginName': health['name'],
                'format': health['format'],
                'src': link['src'],
                'dest': link['dest'],
                'status': link['status'],
                'profilePath': parentDir,
              });
            }
          }
        }
      }

      setState(() {
        _brokenLinks = broken;
        _auditing = false;
      });
      widget.logCallback('Link audit complete. Found ${broken.length} broken shortcuts.', broken.isEmpty ? 'success' : 'warning');
    } catch (e) {
      setState(() => _auditing = false);
      widget.logCallback('Link audit failed: $e', 'error');
    }
  }

  Future<void> _repairProfile(String profilePath) async {
    widget.logCallback('Attempting link repair for: $profilePath', 'info');
    try {
      await _linker.applyProfile(profilePath);
      widget.logCallback('Repair complete.', 'success');
      // Re-run audit
      await _auditLinks();
    } catch (e) {
      widget.logCallback('Repair failed: $e', 'error');
    }
  }

  Future<void> _unlinkProfile(String profilePath) async {
    widget.logCallback('Removing symlinks for: $profilePath', 'info');
    try {
      await _linker.removeProfile(profilePath);
      widget.logCallback('Unlinked successfully.', 'success');
      // Re-run audit
      await _brokenLinks.clear();
      await _auditLinks();
    } catch (e) {
      widget.logCallback('Unlinking failed: $e', 'error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Link Diagnostics & Health Center',
          style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Audit, scan, and repair broken directory junctions and registry values.',
          style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF8C8C8C)),
        ),
        const SizedBox(height: 32),

        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1118).withOpacity(0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Audit Folder Shortcuts', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(color: Colors.white10, height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _libraryPathController,
                      decoration: const InputDecoration(
                        labelText: 'Library Parent Directory',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _browseLibrary,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
                    child: const Text('Browse'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _auditing ? null : _auditLinks,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9254DE)),
                    child: _auditing ? const CircularProgressIndicator() : const Text('Audits Links'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        
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
                Text('Scan & Diagnostics Report', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(color: Colors.white10, height: 32),
                Expanded(
                  child: _brokenLinks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
                              const SizedBox(height: 12),
                              Text('No broken links or mismatched junctions found!', style: GoogleFonts.outfit(color: const Color(0xFF8C8C8C))),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _brokenLinks.length,
                          itemBuilder: (context, idx) {
                            final item = _brokenLinks[idx];
                            return ListTile(
                              title: Text('${item['pluginName']} (${item['format']})', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('Status: ${item['status']}\nPath: ${item['src']}', style: const TextStyle(fontSize: 12)),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.build, color: Colors.green),
                                    onPressed: () => _repairProfile(item['profilePath']),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.link_off, color: Colors.red),
                                    onPressed: () => _unlinkProfile(item['profilePath']),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                )
              ],
            ),
          ),
        ),
      ],
    );
  }
}
