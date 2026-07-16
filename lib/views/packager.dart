import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../models/plugin.dart';
import '../services/scanner.dart';
import '../services/linker.dart';

class PackagerView extends StatefulWidget {
  final void Function(String message, String type) logCallback;

  const PackagerView({super.key, required this.logCallback});

  @override
  State<PackagerView> createState() => _PackagerViewState();
}

class _PackagerViewState extends State<PackagerView> {
  final ScannerService _scanner = ScannerService();
  late LinkerService _linker;

  int _step = 1;
  List<PluginModel> _plugins = [];
  List<PluginModel> _filteredPlugins = [];
  bool _scanning = false;

  String _searchQuery = '';
  String _formatFilter = 'ALL';

  // Config selections
  PluginModel? _selectedPlugin;
  List<Map<String, String>> _resourceSuggestions = [];
  final List<String> _selectedResources = [];
  final List<String> _registryKeys = [];

  // Controllers
  final TextEditingController _targetDirController = TextEditingController();
  final TextEditingController _manualResourceController = TextEditingController();
  final TextEditingController _manualRegistryController = TextEditingController();
  String _linkingStrategy = 'symlink';

  @override
  void initState() {
    super.initState();
    _linker = LinkerService(onLog: widget.logCallback);
  }

  Future<void> _scanPlugins() async {
    setState(() {
      _scanning = true;
    });
    widget.logCallback('Scanning plugin directories...', 'info');

    // Perform scan async-friendly
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      final native = _scanner.scan_native_plugins();
      final winePrefixes = _scanner.getWinePrefixes();
      final List<PluginModel> wine = [];
      for (var prefix in winePrefixes) {
        wine.addAll(_scanner.scan_wine_plugins(prefix));
      }

      setState(() {
        _plugins = [...native, ...wine];
        _applyFilters();
        _scanning = false;
      });
      widget.logCallback('Successfully scanned ${_plugins.length} plugins.', 'success');
    } catch (e) {
      setState(() {
        _scanning = false;
      });
      widget.logCallback('Scanning failed: $e', 'error');
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredPlugins = _plugins.where((p) {
        final matchesSearch = p.name.toLowerCase().contains(_searchQuery.toLowerCase());
        final matchesFormat = _formatFilter == 'ALL' || p.format == _formatFilter;
        return matchesSearch && matchesFormat;
      }).toList();
    });
  }

  Future<void> _configurePlugin(PluginModel plugin) async {
    setState(() {
      _selectedPlugin = plugin;
      _selectedResources.clear();
      _registryKeys.clear();
      _resourceSuggestions.clear();
      _targetDirController.clear();
      _step = 2;
    });

    widget.logCallback('Configuring setup profile for: ${plugin.name}', 'info');

    // Add default registry template for Wine/Windows
    if (plugin.type == 'wine' || Platform.isWindows) {
      _registryKeys.add('HKEY_CURRENT_USER\\Software\\${plugin.name}');
    }

    try {
      final suggestions = await _scanner.findAssociatedResources(
        plugin.name,
        isWine: plugin.type == 'wine',
        prefix: plugin.prefix,
      );

      setState(() {
        _resourceSuggestions = suggestions;
        // Auto-select detected suggestions
        for (var sugg in suggestions) {
          _selectedResources.add(sugg['path']!);
        }
      });
    } catch (e) {
      widget.logCallback('Failed to fetch resource folder suggestions: $e', 'error');
    }
  }

  Future<void> _selectTargetDirectory() async {
    String? result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        _targetDirController.text = result;
      });
    }
  }

  Future<void> _executePackage() async {
    final target = _targetDirController.text.trim();
    if (target.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or specify a destination target path.')),
      );
      return;
    }

    widget.logCallback('Starting plugin relocation & packaging...', 'system');
    try {
      await _linker.packagePlugin(
        name: _selectedPlugin!.name,
        format: _selectedPlugin!.format,
        type: _selectedPlugin!.type,
        mainPath: _selectedPlugin!.path,
        resourcePaths: _selectedResources,
        targetDir: target,
        strategy: _linkingStrategy,
        registryKeys: _registryKeys,
        winePrefix: _selectedPlugin!.prefix,
      );
      widget.logCallback('Packaging completed successfully!', 'success');
      
      setState(() {
        _step = 1;
        _selectedPlugin = null;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relocation complete. Shortcuts symlinked successfully!')),
      );
    } catch (e) {
      widget.logCallback('Critical packing failure: $e', 'error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plugin Packager Wizard',
                  style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Relocate heavy plugins and configs into portable drives seamlessly.',
                  style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF8C8C8C)),
                ),
              ],
            ),
            if (_step > 1)
              ElevatedButton.icon(
                onPressed: () => setState(() => _step = 1),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to List'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF262626)),
              ),
          ],
        ),
        const SizedBox(height: 24),
        
        // Steps Header
        Row(
          children: [
            _buildStepIndicator(1, 'Select Plugin', _step == 1),
            _buildStepSeparator(),
            _buildStepIndicator(2, 'Map Assets & Configurations', _step == 2),
            _buildStepSeparator(),
            _buildStepIndicator(3, 'Run Link Portability', _step == 3),
          ],
        ),
        const SizedBox(height: 32),

        Expanded(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1118).withOpacity(0.65),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: _buildActiveStepContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildStepIndicator(int num, String label, bool active) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? const Color(0xFF9254DE) : Colors.white10,
          ),
          child: Center(
            child: Text(
              '$num',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : const Color(0xFF8C8C8C),
          ),
        ),
      ],
    );
  }

  Widget _buildStepSeparator() {
    return Container(
      width: 40,
      height: 1,
      color: Colors.white10,
      margin: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Widget _buildActiveStepContent() {
    switch (_step) {
      case 1:
        return _buildStep1Select();
      case 2:
        return _buildStep2Map();
      case 3:
        return _buildStep3Execute();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep1Select() {
    return Column(
      children: [
        // Controls Row
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (val) {
                  setState(() => _searchQuery = val);
                  _applyFilters();
                },
                decoration: InputDecoration(
                  hintText: 'Search scanned plugins...',
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF8C8C8C)),
                  fillColor: Colors.black26,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 16),
            DropdownButton<String>(
              value: _formatFilter,
              dropdownColor: const Color(0xFF0F1118),
              items: ['ALL', 'VST2', 'VST3', 'CLAP', 'AAX']
                  .map((fmt) => DropdownMenuItem(value: fmt, child: Text(fmt)))
                  .toList(),
              onChanged: (val) {
                setState(() => _formatFilter = val!);
                _applyFilters();
              },
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: _scanning ? null : _scanPlugins,
              icon: _scanning
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: const Text('Scan Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9254DE),
                height: 48,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // Table content
        Expanded(
          child: _plugins.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.library_music_outlined, size: 48, color: Colors.white24),
                      const SizedBox(height: 12),
                      Text('No scanned plugins yet. Click "Scan Now" to begin.', style: GoogleFonts.outfit(color: const Color(0xFF8C8C8C))),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _filteredPlugins.length,
                  itemBuilder: (context, idx) {
                    final p = _filteredPlugins[idx];
                    final mb = (p.size / (1024 * 1024)).toStringAsFixed(1);
                    return ListTile(
                      title: Text(p.name, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                      subtitle: Text(p.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Chip(label: Text(p.format), backgroundColor: Colors.white10),
                          const SizedBox(width: 12),
                          Text('$mb MB', style: const TextStyle(color: Color(0xFF8C8C8C))),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios, size: 14),
                            onPressed: () => _configurePlugin(p),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStep2Map() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Plugin details banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF9254DE).withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF9254DE).withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.album, size: 40, color: Color(0xFF9254DE)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_selectedPlugin!.name, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(_selectedPlugin!.path, style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF8C8C8C))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        
        // Associated Resource mappings
        Text('Associated Folder Mappings', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        Expanded(
          child: _resourceSuggestions.isEmpty
              ? Center(child: Text('No suggestions found. Add custom directories below.', style: TextStyle(color: const Color(0xFF8C8C8C))))
              : ListView.builder(
                  itemCount: _resourceSuggestions.length,
                  itemBuilder: (context, idx) {
                    final path = _resourceSuggestions[idx]['path']!;
                    final desc = _resourceSuggestions[idx]['description']!;
                    final isChecked = _selectedResources.contains(path);
                    return CheckboxListTile(
                      value: isChecked,
                      title: Text(path, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                      subtitle: Text(desc, style: const TextStyle(fontSize: 11, color: Color(0xFF8C8C8C))),
                      onChanged: (val) {
                        setState(() {
                          if (val!) {
                            _selectedResources.add(path);
                          } else {
                            _selectedResources.remove(path);
                          }
                        });
                      },
                    );
                  },
                ),
        ),
        
        // Manual resource adder
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _manualResourceController,
                decoration: const InputDecoration(
                  hintText: 'Add custom resources path manually...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Color(0xFF13C2C2)),
              onPressed: () {
                final path = _manualResourceController.text.trim();
                if (path.isNotEmpty) {
                  setState(() {
                    _selectedResources.add(path);
                    _resourceSuggestions.add({'path': path, 'description': 'Manually added configuration'});
                    _manualResourceController.clear();
                  });
                }
              },
            ),
          ],
        ),

        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => setState(() => _step = 3),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9254DE)),
          child: const Text('Next: Packing Configs'),
        ),
      ],
    );
  }

  Widget _buildStep3Execute() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Configure Packing Target', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _targetDirController,
                decoration: const InputDecoration(
                  labelText: 'Portable Target Directory',
                  hintText: 'e.g. D:\\PluginsLibrary\\MyPluginName',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _selectTargetDirectory,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
              child: const Text('Browse'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        DropdownButtonFormField<String>(
          value: _linkingStrategy,
          decoration: const InputDecoration(labelText: 'Linking Strategy', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'symlink', child: Text('Symbolic Link / Windows Junction')),
            DropdownMenuItem(value: 'hardlink', child: Text('Hard Link (same drive partition only)')),
          ],
          onChanged: (val) => setState(() => _linkingStrategy = val!),
        ),
        
        const SizedBox(height: 32),
        const Spacer(),
        Row(
          children: [
            ElevatedButton(
              onPressed: () => setState(() => _step = 2),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
              child: const Text('Back'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: _executePackage,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Relocate & Symlink'),
            ),
          ],
        ),
      ],
    );
  }
}
