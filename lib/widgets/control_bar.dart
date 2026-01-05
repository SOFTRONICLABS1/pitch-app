import 'package:flutter/material.dart';

class ControlBar extends StatelessWidget {
  const ControlBar({
    super.key,
    required this.listening,
    required this.recording,
    required this.errorMessage,
    required this.onStart,
    required this.onStop,
    required this.onOpenSettings,
    required this.onOpenRecordings,
    required this.onOpenTanpura,
    required this.onToggleRecording,
  });

  final bool listening;
  final bool recording;
  final String? errorMessage;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenRecordings;
  final VoidCallback onOpenTanpura;
  final VoidCallback onToggleRecording;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF262B2F),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Column(
        children: [
          if (errorMessage != null) ...[
            Text(
              errorMessage ?? '',
              style: const TextStyle(color: Colors.redAccent),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Center(
                  child: IconButton(
                    icon: const Icon(Icons.music_note, size: 30),
                    onPressed: onOpenTanpura,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: IconButton(
                    icon: const Icon(Icons.queue_music, size: 30),
                    onPressed: onOpenRecordings,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: IconButton(
                    icon: Icon(
                      listening ? Icons.pause : Icons.play_arrow,
                      size: 36,
                    ),
                    onPressed: listening ? onStop : onStart,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: IconButton(
                    icon: Icon(
                      recording
                          ? Icons.stop_circle_outlined
                          : Icons.fiber_manual_record,
                      color: Colors.red,
                    ),
                    onPressed: onToggleRecording,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: IconButton(
                    icon: const Icon(Icons.settings, size: 30),
                    onPressed: onOpenSettings,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
