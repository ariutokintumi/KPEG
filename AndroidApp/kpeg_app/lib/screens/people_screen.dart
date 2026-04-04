import 'dart:io';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/people_provider.dart';
import '../widgets/kpeg_gradient_background.dart';
import 'person_detail_screen.dart';

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PeopleProvider>().loadPeople();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PeopleProvider>();

    return KpegGradientBackground(
      child: SafeArea(
        child: Column(
          children: [
            // Cabecera
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: KpegTheme.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: KpegTheme.accent.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(Icons.people_rounded,
                        size: 28, color: KpegTheme.accent),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'People',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${provider.people.length} profile${provider.people.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: KpegTheme.accent,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),

            // Lista o vacío
            Expanded(
              child: provider.people.isEmpty
                  ? _emptyView()
                  : _listView(provider),
            ),

            // Botón añadir
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChangeNotifierProvider.value(
                          value: provider,
                          child: const PersonDetailScreen(),
                        ),
                      ),
                    );
                    // Recargar al volver
                    if (mounted) provider.loadPeople();
                  },
                  icon: const Icon(Icons.person_add_rounded),
                  label: const Text(
                    'Add person',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KpegTheme.accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_add_rounded,
              size: 56, color: KpegTheme.accent.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            'Add people to\nidentify them in your photos',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _listView(PeopleProvider provider) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: provider.people.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final person = provider.people[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: KpegTheme.accent.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: KpegTheme.accent.withValues(alpha: 0.2),
                backgroundImage: person.thumbnailPath != null
                    ? FileImage(File(person.thumbnailPath!))
                    : null,
                child: person.thumbnailPath == null
                    ? Text(
                        person.name.isNotEmpty
                            ? person.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: KpegTheme.accent,
                            fontSize: 20,
                            fontWeight: FontWeight.w700),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      person.visibleUserId,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Eliminar
              IconButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete person'),
                      content: Text('Delete ${person.name}?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel')),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete',
                                style: TextStyle(color: Colors.redAccent))),
                      ],
                    ),
                  );
                  if (confirm == true) provider.deletePerson(person.visibleUserId);
                },
                icon: Icon(Icons.delete_outline,
                    color: Colors.white.withValues(alpha: 0.3), size: 20),
              ),
            ],
          ),
        );
      },
    );
  }
}
