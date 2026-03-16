// lib/main.dart
// Entry point. Sets up the provider tree, initialises notification service,
// and boots go_router.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/album_provider.dart';
import 'providers/image_provider.dart';
import 'providers/notifiers.dart';
import 'providers/selection_provider.dart';
import 'providers/tag_provider.dart';
import 'router/app_router.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const PhotoVaultApp());
}

class PhotoVaultApp extends StatelessWidget {
  const PhotoVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AlbumProvider()),
        ChangeNotifierProvider(create: (_) => TagProvider()),
        ChangeNotifierProvider(create: (_) => DeviceImageProvider()),
        ChangeNotifierProvider(create: (_) => SelectionProvider()),
        // SelectionCountNotifier stays in sync automatically via
        // ChangeNotifierProxyProvider — no manual addListener needed.
        ChangeNotifierProxyProvider<SelectionProvider, SelectionCountNotifier>(
          create: (_) => SelectionCountNotifier(),
          update: (_, sel, notifier) => notifier!..update(sel.count),
        ),
        ChangeNotifierProvider(create: (_) => FilteredListNotifier()),
      ],
      child: const _AppRoot(),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Wire AlbumProvider to DeviceImageProvider so image mutations
      // automatically invalidate the filter cache.
      context.read<AlbumProvider>().attachImageProvider(
            context.read<DeviceImageProvider>(),
          );
      // Eagerly load albums and tags so the filter sheet has data on first open.
      context.read<AlbumProvider>().load();
      context.read<TagProvider>().load();
      // Load persisted selection.
      context.read<SelectionProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PhotoVault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: appRouter,
    );
  }
}
