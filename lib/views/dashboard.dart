import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DashboardView extends StatelessWidget {
  final void Function(String tab) onNavigate;

  const DashboardView({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'System Dashboard',
          style: GoogleFonts.outfit(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Overview of your local and portable audio plugin environment.',
          style: GoogleFonts.outfit(
            fontSize: 14,
            color: const Color(0xFF8C8C8C),
          ),
        ),
        const SizedBox(height: 32),
        
        // Stats Grid
        Row(
          children: [
            Expanded(child: _buildStatCard(Icons.settings_input_component, 'Total Plugins', 'Scan Required', const Color(0xFF9254DE))),
            const SizedBox(width: 20),
            Expanded(child: _buildStatCard(Icons.link, 'Active Links', '0', const Color(0xFF13C2C2))),
            const SizedBox(width: 20),
            Expanded(child: _buildStatCard(Icons.computer, 'Platform Target', Platform.operatingSystem.toUpperCase(), const Color(0xFF1890FF))),
          ],
        ),
        
        const SizedBox(height: 40),
        
        // Quick Actions & Setup Guide
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _buildGlassCard(
                title: 'Cross-Platform Link System',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How SymLinkr secures your audio plugins:',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    _buildGuideItem(Icons.check_circle_outline, 'Relocates large VST/CLAP/AAX binaries onto external SSDs.'),
                    _buildGuideItem(Icons.check_circle_outline, 'Backs up licensing data and configuration entries.'),
                    _buildGuideItem(Icons.check_circle_outline, 'For Windows, uses NTFS Directory Junctions to bypass Admin/UAC limits.'),
                    _buildGuideItem(Icons.check_circle_outline, 'For Wine/Linux, automatically links folders and imports .reg files.'),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 1,
              child: _buildGlassCard(
                title: 'Quick Actions',
                child: Column(
                  children: [
                    _buildActionButton(context, 'Scan Local Plugins', Icons.search, () => onNavigate('packager'), isPrimary: true),
                    const SizedBox(height: 12),
                    _buildActionButton(context, 'Deploy Portable Folder', Icons.input, () => onNavigate('deployer'), isPrimary: false),
                    const SizedBox(height: 12),
                    _buildActionButton(context, 'Check Link Health', Icons.health_and_safety, () => onNavigate('health'), isPrimary: false),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1118).withOpacity(0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF8C8C8C),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1118).withOpacity(0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Divider(color: Colors.white10, height: 32),
          child,
        ],
      ),
    );
  }

  Widget _buildGuideItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF13C2C2), size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: const Color(0xFF8C8C8C),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, String text, IconData icon, VoidCallback onPressed, {required bool isPrimary}) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(text),
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: isPrimary ? const Color(0xFF9254DE) : const Color(0xFF262626),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
      ),
    );
  }
}
