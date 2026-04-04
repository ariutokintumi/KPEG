import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/objects_provider.dart';
import '../providers/people_provider.dart';
import '../providers/places_provider.dart';
import '../widgets/kpeg_gradient_background.dart';
import 'object_detail_screen.dart';
import 'person_detail_screen.dart';
import 'place_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PeopleProvider>().loadPeople();
      context.read<PlacesProvider>().loadPlaces();
      context.read<ObjectsProvider>().loadObjects();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KpegGradientBackground(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: KpegTheme.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: KpegTheme.accent.withValues(alpha: 0.4),
                          width: 1.5),
                    ),
                    child: const Icon(Icons.local_library_rounded,
                        size: 28, color: KpegTheme.accent),
                  ),
                  const SizedBox(height: 8),
                  const Text('Library',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 2)),
                ],
              ),
            ),

            // 3 tabs
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: KpegTheme.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: KpegTheme.accent,
                unselectedLabelColor: Colors.white54,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontSize: 12),
                tabs: const [
                  Tab(icon: Icon(Icons.people_rounded, size: 18), text: 'People'),
                  Tab(icon: Icon(Icons.place_rounded, size: 18), text: 'Places'),
                  Tab(icon: Icon(Icons.category_rounded, size: 18), text: 'Objects'),
                ],
              ),
            ),

            const SizedBox(height: 8),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _PeopleTab(),
                  _PlacesTab(),
                  _ObjectsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════
// PEOPLE TAB
// ══════════════════════════════════════

class _PeopleTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PeopleProvider>();
    return Column(
      children: [
        Expanded(
          child: provider.people.isEmpty
              ? _empty('Add people to identify\nthem in your photos',
                  Icons.person_add_rounded)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: provider.people.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _personTile(context, provider, provider.people[i]),
                ),
        ),
        _addButton(context, 'Add person', Icons.person_add_rounded, () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChangeNotifierProvider.value(
                value: provider,
                child: const PersonDetailScreen(),
              ),
            ),
          );
          provider.loadPeople();
        }),
      ],
    );
  }

  Widget _personTile(BuildContext context, PeopleProvider provider, person) {
    return _LibraryTile(
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: KpegTheme.accent.withValues(alpha: 0.2),
        backgroundImage: person.thumbnailPath != null
            ? FileImage(File(person.thumbnailPath!))
            : null,
        child: person.thumbnailPath == null
            ? Text(person.name[0].toUpperCase(),
                style: const TextStyle(
                    color: KpegTheme.accent, fontWeight: FontWeight.w700))
            : null,
      ),
      title: person.name,
      subtitle: '${person.selfieCount} selfies',
      onDelete: () => _confirmDelete(
          context, 'Delete ${person.name}?', () => provider.deletePerson(person.visibleUserId)),
    );
  }
}

// ══════════════════════════════════════
// PLACES TAB
// ══════════════════════════════════════

class _PlacesTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlacesProvider>();
    return Column(
      children: [
        Expanded(
          child: provider.places.isEmpty
              ? _empty('Add indoor places to\nimprove reconstruction',
                  Icons.add_location_alt_rounded)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: provider.places.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _placeTile(context, provider, provider.places[i]),
                ),
        ),
        _addButton(context, 'Add place', Icons.add_location_alt_rounded, () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChangeNotifierProvider.value(
                value: provider,
                child: const PlaceDetailScreen(),
              ),
            ),
          );
          provider.loadPlaces();
        }),
      ],
    );
  }

  Widget _placeTile(BuildContext context, PlacesProvider provider, place) {
    return _LibraryTile(
      leading: _thumbnailOrIcon(place.thumbnailPath, Icons.place_rounded),
      title: place.name,
      subtitle: [place.floor, place.building]
          .where((s) => s != null && s.isNotEmpty)
          .join(', '),
      extra: '${place.photoCount} photos',
      onDelete: () => _confirmDelete(
          context, 'Delete ${place.name}?', () => provider.deletePlace(place.placeId)),
    );
  }
}

// ══════════════════════════════════════
// OBJECTS TAB
// ══════════════════════════════════════

class _ObjectsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ObjectsProvider>();
    return Column(
      children: [
        Expanded(
          child: provider.objects.isEmpty
              ? _empty('Add indoor objects to\nimprove reconstruction',
                  Icons.category_rounded)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: provider.objects.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _objectTile(context, provider, provider.objects[i]),
                ),
        ),
        _addButton(context, 'Add object', Icons.add_circle_outline_rounded, () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChangeNotifierProvider.value(
                value: provider,
                child: const ObjectDetailScreen(),
              ),
            ),
          );
          provider.loadObjects();
        }),
      ],
    );
  }

  Widget _objectTile(BuildContext context, ObjectsProvider provider, obj) {
    return _LibraryTile(
      leading: _thumbnailOrIcon(obj.thumbnailPath, Icons.category_rounded),
      title: obj.name,
      subtitle: obj.category,
      extra: '${obj.photoCount} photos',
      onDelete: () => _confirmDelete(
          context, 'Delete ${obj.name}?', () => provider.deleteObject(obj.objectId)),
    );
  }
}

// ══════════════════════════════════════
// SHARED WIDGETS
// ══════════════════════════════════════

class _LibraryTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final String? extra;
  final VoidCallback onDelete;

  const _LibraryTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.extra,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KpegTheme.accent.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                if (extra != null)
                  Text(extra!,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline,
                color: Colors.white.withValues(alpha: 0.3), size: 20),
          ),
        ],
      ),
    );
  }
}

Widget _thumbnailOrIcon(String? thumbnailPath, IconData fallbackIcon) {
  if (thumbnailPath != null) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(
        File(thumbnailPath),
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _iconBox(fallbackIcon),
      ),
    );
  }
  return _iconBox(fallbackIcon);
}

Widget _iconBox(IconData icon) {
  return Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: KpegTheme.accent.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, color: KpegTheme.accent, size: 22),
  );
}

Widget _empty(String text, IconData icon) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 48, color: KpegTheme.accent.withValues(alpha: 0.3)),
        const SizedBox(height: 12),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14)),
      ],
    ),
  );
}

Widget _addButton(BuildContext context, String label, IconData icon, VoidCallback onPressed) {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: KpegTheme.accent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ),
  );
}

Future<void> _confirmDelete(BuildContext context, String message, VoidCallback onConfirm) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete'),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
      ],
    ),
  );
  if (confirm == true) onConfirm();
}
