import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LogsView extends StatelessWidget {
  final List<Map<String, String>> logs;
  final VoidCallback clearCallback;

  const LogsView({super.key, required this.logs, required this.clearCallback});

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
                  'System Activity Logs',
                  style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Live command-line stdout displaying filesystem link actions.',
                  style: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF8C8C8C)),
                ),
              ],
            ),
            ElevatedButton.icon(
              onPressed: clearCallback,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Clear Logs'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF262626)),
            ),
          ],
        ),
        const SizedBox(height: 32),
        
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, idx) {
                final item = logs[idx];
                final color = _getLogColor(item['type']!);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Text(
                    '[${item['timestamp']}] [${item['type']!.toUpperCase()}] ${item['message']}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: color,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Color _getLogColor(String type) {
    switch (type) {
      case 'system':
        return const Color(0xFF1890FF);
      case 'success':
        return const Color(0xFF52C41A);
      case 'warning':
        return const Color(0xFFFAAD14);
      case 'error':
        return const Color(0xFFFF4D4F);
      default:
        return const Color(0xFFD9D9D9);
    }
  }
}
