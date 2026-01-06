import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../main.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'recordings_screen.dart';
import 'vocal_tracker.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {},
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                child: Text(
                  'Shruti Sadhana',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Profile'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () => _signOut(context),
              ),
            ],
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            _MenuTile(
              icon: Icons.graphic_eq,
              label: 'Practice',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PitchHomePage()),
                );
              },
            ),
            _MenuTile(
              icon: Icons.library_music,
              label: 'Recordings',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RecordingsScreen()),
                );
              },
            ),
            _MenuTile(
              icon: Icons.mic,
              label: 'Vocal Tracker',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RecordingsScreen(
                      onSelect: (recording) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => VocalTrackerScreen(
                              recording: recording,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42),
              const SizedBox(height: 8),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}
