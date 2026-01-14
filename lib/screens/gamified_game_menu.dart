import 'package:flutter/material.dart';

import '../models/recording.dart';
import 'gamified_vocal_tracker.dart';

class GamifiedGameMenuScreen extends StatelessWidget {
  const GamifiedGameMenuScreen({
    super.key,
    required this.recording,
  });

  final RecordingEntry recording;

  @override
  Widget build(BuildContext context) {
    final options = [
      _GameMenuOption(
        title: 'Arcade Neon',
        subtitle: 'Glows, HUD grid, fast arcade vibe',
        theme: GameVisualTheme.arcade,
        gradient: const LinearGradient(
          colors: [Color(0xFF10101A), Color(0xFF2C2158)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        accent: const Color(0xFF63F0FF),
      ),
      _GameMenuOption(
        title: 'Retro Shooter',
        subtitle: 'Warm CRT tones, pixel power',
        theme: GameVisualTheme.retro,
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0D12), Color(0xFF432013)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        accent: const Color(0xFFFFD369),
      ),
      _GameMenuOption(
        title: 'Tactical Ops',
        subtitle: 'Clean metal HUD, precision focus',
        theme: GameVisualTheme.tactical,
        gradient: const LinearGradient(
          colors: [Color(0xFF0E1418), Color(0xFF20323A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        accent: const Color(0xFF5AD4FF),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E12),
      appBar: AppBar(
        title: const Text('Game Modes'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final option = options[index];
          return _GameModeCard(
            option: option,
            onPlay: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GamifiedVocalTrackerScreen(
                    recording: recording,
                    theme: option.theme,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _GameMenuOption {
  const _GameMenuOption({
    required this.title,
    required this.subtitle,
    required this.theme,
    required this.gradient,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final GameVisualTheme theme;
  final LinearGradient gradient;
  final Color accent;
}

class _GameModeCard extends StatelessWidget {
  const _GameModeCard({
    required this.option,
    required this.onPlay,
  });

  final _GameMenuOption option;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onPlay,
      child: Ink(
        decoration: BoxDecoration(
          gradient: option.gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: option.accent.withOpacity(0.25),
              blurRadius: 20,
              spreadRadius: -8,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GamePreview(accent: option.accent),
              const SizedBox(height: 16),
              Text(
                option.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF7F7FB),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                option.subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFFB4B7C7),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GamePreview extends StatelessWidget {
  const _GamePreview({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _HudGridPainter(accent: accent.withOpacity(0.25)),
            ),
          ),
          Positioned(
            top: 16,
            left: 24,
            child: _TargetBadge(accent: accent),
          ),
          Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                height: 10,
                width: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 34,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 2,
                height: 48,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetBadge extends StatelessWidget {
  const _TargetBadge({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      width: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent, width: 2),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.45),
            blurRadius: 12,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Center(
        child: Container(
          height: 12,
          width: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent,
          ),
        ),
      ),
    );
  }
}

class _HudGridPainter extends CustomPainter {
  _HudGridPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent
      ..strokeWidth = 1;
    const gap = 24.0;
    for (var x = gap; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = gap; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HudGridPainter oldDelegate) {
    return oldDelegate.accent != accent;
  }
}
