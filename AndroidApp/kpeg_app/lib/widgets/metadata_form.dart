import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/place.dart';

class MetadataForm extends StatelessWidget {
  final bool isOutdoor;
  final ValueChanged<bool> onOutdoorChanged;
  final String sceneHint;
  final ValueChanged<String> onSceneHintChanged;
  final String tagsText;
  final ValueChanged<String> onTagsChanged;
  final String indoorDescription;
  final ValueChanged<String> onIndoorDescriptionChanged;
  // Place selector
  final List<Place> nearbyPlaces;
  final Place? selectedPlace;
  final ValueChanged<Place?> onPlaceChanged;

  const MetadataForm({
    super.key,
    required this.isOutdoor,
    required this.onOutdoorChanged,
    required this.sceneHint,
    required this.onSceneHintChanged,
    required this.tagsText,
    required this.onTagsChanged,
    required this.indoorDescription,
    required this.onIndoorDescriptionChanged,
    this.nearbyPlaces = const [],
    this.selectedPlace,
    required this.onPlaceChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KpegTheme.accent.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Indoor/Outdoor segmented button
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Indoor'),
                  icon: Icon(Icons.home_rounded, size: 18),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Outdoor'),
                  icon: Icon(Icons.wb_sunny_rounded, size: 18),
                ),
              ],
              selected: {isOutdoor},
              onSelectionChanged: (s) => onOutdoorChanged(s.first),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return KpegTheme.accent.withValues(alpha: 0.2);
                  }
                  return Colors.transparent;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return KpegTheme.accent;
                  }
                  return Colors.white54;
                }),
                side: WidgetStateProperty.all(
                  BorderSide(color: KpegTheme.accent.withValues(alpha: 0.3)),
                ),
              ),
            ),
          ),

          // Place selector (only when indoor)
          if (!isOutdoor) ...[
            const SizedBox(height: 12),
            _PlaceSelector(
              places: nearbyPlaces,
              selected: selectedPlace,
              onChanged: onPlaceChanged,
            ),

            const SizedBox(height: 4),
            TextField(
              onChanged: onIndoorDescriptionChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Details (e.g. "near the window")',
                hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
                prefixIcon: const Icon(Icons.edit_note_rounded,
                    color: KpegTheme.accent, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
              ),
            ),
          ],

          const SizedBox(height: 4),

          // Scene hint
          TextField(
            onChanged: onSceneHintChanged,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'What\'s happening? (e.g. "birthday party")',
              hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
              prefixIcon: const Icon(Icons.notes_rounded,
                  color: KpegTheme.accent, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: InputBorder.none,
            ),
          ),

          // Tags
          TextField(
            onChanged: onTagsChanged,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Tags (e.g. "hackathon, team")',
              hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
              prefixIcon: const Icon(Icons.label_rounded,
                  color: KpegTheme.accent, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }
}

/// Searchable place selector dropdown
class _PlaceSelector extends StatelessWidget {
  final List<Place> places;
  final Place? selected;
  final ValueChanged<Place?> onChanged;

  const _PlaceSelector({
    required this.places,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPlacePicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected != null
                ? KpegTheme.accent.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.place_rounded,
                color: selected != null ? KpegTheme.accent : Colors.white38,
                size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selected?.displayLabel ?? 'Select a place...',
                style: TextStyle(
                  color: selected != null
                      ? KpegTheme.accent
                      : Colors.white.withValues(alpha: 0.3),
                  fontSize: 14,
                ),
              ),
            ),
            if (selected != null)
              GestureDetector(
                onTap: () => onChanged(null),
                child: Icon(Icons.close,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.4)),
              )
            else
              Icon(Icons.arrow_drop_down,
                  color: Colors.white.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }

  void _showPlacePicker(BuildContext context) {
    if (places.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No places registered. Add places in the Library tab.'),
          backgroundColor: KpegTheme.accent,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: KpegTheme.bgDark1,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select place',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: places.map((place) => ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: KpegTheme.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.place_rounded,
                          color: KpegTheme.accent, size: 18),
                    ),
                    title: Text(place.name,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: place.description != null
                        ? Text(
                            place.description!,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 12),
                          )
                        : null,
                    onTap: () {
                      onChanged(place);
                      Navigator.pop(ctx);
                    },
                  )).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
