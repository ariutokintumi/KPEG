import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/people_provider.dart';
import '../providers/places_provider.dart';
import '../widgets/kpeg_gradient_background.dart';
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
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PeopleProvider>().loadPeople();
      context.read<PlacesProvider>().loadPlaces();
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
            // Header
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
                    child: const Icon(Icons.library_books_rounded,
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

            // Tab bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
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
                tabs: const [
                  Tab(
                    icon: Icon(Icons.people_rounded, size: 20),
                    text: 'People',
                  ),
                  Tab(
                    icon: Icon(Icons.place_rounded, size: 20),
                    text: 'Places',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _PeopleTab(),
                  _PlacesTab(),
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
          child: provider.people.isEmpty ? _emptyPeople() : _peopleList(context, provider),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
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
                provider.loadPeople();
              },
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Add person',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: KpegTheme.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyPeople() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_add_rounded,
              size: 48, color: KpegTheme.accent.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text('Add people to identify\nthem in your photos',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _peopleList(BuildContext context, PeopleProvider provider) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: provider.people.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final person = provider.people[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: KpegTheme.accent.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              CircleAvatar(
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(person.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    Text('${person.selfieCount} selfies',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12)),
                  ],
                ),
              ),
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
          child: provider.places.isEmpty ? _emptyPlaces() : _placesList(context, provider),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () async {
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
              },
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('Add place',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: KpegTheme.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyPlaces() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_location_alt_rounded,
              size: 48, color: KpegTheme.accent.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text('Add indoor places to\nimprove photo reconstruction',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _placesList(BuildContext context, PlacesProvider provider) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: provider.places.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final place = provider.places[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: KpegTheme.accent.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: KpegTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.place_rounded,
                    color: KpegTheme.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(place.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    if (place.building != null || place.floor != null)
                      Text(
                        [place.floor, place.building]
                            .where((s) => s != null && s.isNotEmpty)
                            .join(', '),
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12),
                      ),
                    Text('${place.photoCount} photos',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 11)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete place'),
                      content: Text('Delete ${place.name}?'),
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
                  if (confirm == true) provider.deletePlace(place.placeId);
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
