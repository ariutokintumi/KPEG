import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'providers/capture_provider.dart';
import 'providers/gallery_provider.dart';
import 'providers/people_provider.dart';
import 'services/api_service.dart';
import 'services/database_service.dart';
import 'services/kpeg_repository.dart';
import 'services/people_repository.dart';
import 'services/face_detection_service.dart';
import 'services/sensor_service.dart';
import 'screens/capture_screen.dart';
import 'screens/gallery_screen.dart';
import 'screens/people_screen.dart';

void main() {
  runApp(const KpegApp());
}

class KpegApp extends StatelessWidget {
  const KpegApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dbService = DatabaseService();
    final apiService = ApiService();
    final kpegRepo = KpegRepository(dbService);
    final peopleRepo = PeopleRepository(dbService);
    final sensorService = SensorService();
    final faceDetectionService = FaceDetectionService();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => CaptureProvider(
            api: apiService,
            kpegRepo: kpegRepo,
            sensors: sensorService,
            faceDetection: faceDetectionService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => GalleryProvider(
            kpegRepo: kpegRepo,
            api: apiService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => PeopleProvider(repo: peopleRepo),
        ),
      ],
      child: MaterialApp(
        title: 'KPEG',
        debugShowCheckedModeBanner: false,
        theme: KpegTheme.darkTheme,
        home: const MainShell(),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final _screens = const [
    CaptureScreen(),
    GalleryScreen(),
    PeopleScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          // Refrescar datos al cambiar de tab
          if (index == 1) {
            context.read<GalleryProvider>().loadFiles();
          } else if (index == 2) {
            context.read<PeopleProvider>().loadPeople();
          }
          setState(() => _currentIndex = index);
        },
        backgroundColor: KpegTheme.bgDark1,
        indicatorColor: KpegTheme.accent.withValues(alpha: 0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon:
                Icon(Icons.camera_alt_rounded, color: KpegTheme.accent),
            label: 'Captura',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon:
                Icon(Icons.photo_library_rounded, color: KpegTheme.accent),
            label: 'Galería',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon:
                Icon(Icons.people_rounded, color: KpegTheme.accent),
            label: 'Personas',
          ),
        ],
      ),
    );
  }
}
