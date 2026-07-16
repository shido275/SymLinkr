import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import 'views/dashboard.dart';
import 'views/packager.dart';
import 'views/deployer.dart';
import 'views/health.dart';
import 'views/logs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(1024, 768),
      center: true,
      backgroundColor: Colors.transparent,
      title: 'SymLinkr | Audio Plugin Portability Manager',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const SymLinkrApp());
}

class SymLinkrApp extends StatelessWidget {
  const SymLinkrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SymLinkr',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF08090D),
        primaryColor: const Color(0xFF9254DE),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF9254DE),
          secondary: Color(0xFF13C2C2),
          surface: Color(0xFF0F1118),
          background: Color(0xFF08090D),
          error: Color(0xFFFF4D4F),
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
      ),
      home: const MainLayoutScreen(),
    );
  }
}

class MainLayoutScreen extends StatefulWidget {
  const MainLayoutScreen({super.key});

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  String _activeTab = 'dashboard';
  final List<Map<String, String>> _logs = [];

  void _addLog(String message, String type) {
    setState(() {
      _logs.add({
        'timestamp': DateTime.now().toLocal().toString().split(' ')[1].substring(0, 8),
        'message': message,
        'type': type,
      });
    });
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
      _addLog('Activity logs cleared.', 'system');
    });
  }

  @override
  void initState() {
    super.initState();
    _addLog('SymLinkr UI loaded. Awaiting instructions...', 'system');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background glowing spots
          Positioned(
            top: -100,
            left: 100,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF9254DE).withOpacity(0.08),
                backgroundBlendMode: BlendMode.screen,
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: 100,
            child: Container(
              width: 450,
              height: 450,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF13C2C2).withOpacity(0.08),
                backgroundBlendMode: BlendMode.screen,
              ),
            ),
          ),
          
          Row(
            children: [
              // Sidebar Navigation
              Container(
                width: 260,
                color: const Color(0xFF0F1118),
                border: const Border(right: BorderSide(color: Colors.white10)),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Brand Header
                    Padding(
                      padding: const EdgeInsets.only(bottom: 40, top: 10),
                      child: Row(
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Color(0xFF13C2C2), Color(0xFF9254DE)],
                            ).createShader(bounds),
                            child: const Icon(
                              Icons.link_off,
                              size: 28,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'SymLinkr',
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Nav Items
                    Expanded(
                      child: Column(
                        children: [
                          _buildNavItem('dashboard', Icons.analytics_outlined, 'Dashboard'),
                          const SizedBox(height: 8),
                          _buildNavItem('packager', Icons.archive_outlined, 'Scan & Pack'),
                          const SizedBox(height: 8),
                          _buildNavItem('deployer', Icons.unarchive_outlined, 'Deploy & Link'),
                          const SizedBox(height: 8),
                          _buildNavItem('health', Icons.health_and_safety_outlined, 'Health Center'),
                          const SizedBox(height: 8),
                          _buildNavItem('logs', Icons.terminal_outlined, 'Activity Logs'),
                        ],
                      ),
                    ),
                    
                    // Sidebar Footer
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF52C41A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Native Environment Active',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Main Tab Content Area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: _buildActiveTabContent(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(String tabId, IconData icon, String title) {
    final isActive = _activeTab == tabId;
    return InkWell(
      onTap: () {
        setState(() {
          _activeTab = tabId;
        });
        _addLog('Switched to tab: $tabId', 'system');
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: isActive
              ? LinearGradient(
                  colors: [
                    const Color(0xFF9254DE).withOpacity(0.2),
                    const Color(0xFF1890FF).withOpacity(0.04),
                  ],
                )
              : null,
          border: isActive ? Border.all(color: const Color(0xFF9254DE).withOpacity(0.3)) : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isActive ? Colors.white : const Color(0xFF8C8C8C),
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isActive ? Colors.white : const Color(0xFF8C8C8C),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (_activeTab) {
      case 'dashboard':
        return DashboardView(onNavigate: (tab) {
          setState(() {
            _activeTab = tab;
          });
        });
      case 'packager':
        return PackagerView(logCallback: _addLog);
      case 'deployer':
        return DeployerView(logCallback: _addLog);
      case 'health':
        return HealthView(logCallback: _addLog);
      case 'logs':
        return LogsView(logs: _logs, clearCallback: _clearLogs);
      default:
        return const Center(child: Text('Coming Soon'));
    }
  }
}
