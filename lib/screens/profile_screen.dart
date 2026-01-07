import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/user_prefs.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authEmail = FirebaseAuth.instance.currentUser?.email;
    final authName = FirebaseAuth.instance.currentUser?.displayName;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: Center(
        child: FutureBuilder<List<String?>>(
          future: Future.wait([
            UserPrefs.loadEmail(),
            UserPrefs.loadName(),
          ]),
          initialData: [authEmail, authName],
          builder: (context, snapshot) {
            final storedEmail = snapshot.data?[0];
            final storedName = snapshot.data?[1];
            final email =
                authEmail ?? storedEmail ?? 'profile@shrutisadhana.app';
            final name = authName ??
                storedName ??
                _fallbackNameFromEmail(email) ??
                'Demo Profile';
            return Card(
              margin: const EdgeInsets.all(20),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(
                      radius: 36,
                      child: Icon(Icons.person, size: 40),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(email),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

String? _fallbackNameFromEmail(String? email) {
  if (email == null || email.trim().isEmpty) {
    return null;
  }
  final parts = email.split('@');
  if (parts.isEmpty) return null;
  final raw = parts.first.replaceAll('.', ' ').replaceAll('_', ' ').trim();
  if (raw.isEmpty) return null;
  return raw
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}
