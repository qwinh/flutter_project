import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';

import 'managers/album_manager.dart';
import 'managers/tag_manager.dart';
import 'managers/image_selection_manager.dart';
import 'services/notification_service.dart';

import 'uis/albums/albums_view.dart';
import 'uis/albums/album_view.dart';
import 'uis/albums/album_add.dart';
import 'uis/tags/tags_view.dart';
import 'uis/tags/tag_view.dart';
import 'uis/tags/tag_add.dart';
import 'uis/images/images_view.dart';
import 'uis/images/image_view.dart';
import 'uis/images/images_selected_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  runApp(const AlbumManagerApp());
}

class AlbumManagerApp extends StatelessWidget {
  const AlbumManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AlbumManager()..loadAlbums()),
        ChangeNotifierProvider(create: (_) => TagManager()..loadTags()),
        ChangeNotifierProvider(
          create: (_) => ImageSelectionManager()..loadSelections(),
        ),
      ],
      child: MaterialApp.router(
        title: 'Album Manager',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6750A4),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
          cardTheme: CardThemeData(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
          ),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6750A4),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
          cardTheme: CardThemeData(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
          ),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        themeMode: ThemeMode.system,
        routerConfig: _router,
      ),
    );
  }
}

// Custom slide transition page
CustomTransitionPage<T> _buildPageWithSlideTransition<T>({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(1.0, 0.0);
      const end = Offset.zero;
      const curve = Curves.easeInOut;
      final tween = Tween(
        begin: begin,
        end: end,
      ).chain(CurveTween(curve: curve));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
    transitionDuration: const Duration(milliseconds: 300),
  );
}

// Fade transition for top-level routes
CustomTransitionPage<T> _buildPageWithFadeTransition<T>({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 250),
  );
}

final GoRouter _router = GoRouter(
  initialLocation: '/albums',
  routes: [
    // --- Albums ---
    GoRoute(
      path: '/albums',
      pageBuilder: (context, state) =>
          _buildPageWithFadeTransition(state: state, child: const AlbumsView()),
      routes: [
        GoRoute(
          path: 'add',
          pageBuilder: (context, state) => _buildPageWithSlideTransition(
            state: state,
            child: const AlbumAdd(),
          ),
        ),
        GoRoute(
          path: ':id',
          pageBuilder: (context, state) {
            final id = int.parse(state.pathParameters['id']!);
            return _buildPageWithSlideTransition(
              state: state,
              child: AlbumView(albumId: id),
            );
          },
        ),
      ],
    ),
    // --- Tags ---
    GoRoute(
      path: '/tags',
      pageBuilder: (context, state) =>
          _buildPageWithFadeTransition(state: state, child: const TagsView()),
      routes: [
        GoRoute(
          path: 'add',
          pageBuilder: (context, state) => _buildPageWithSlideTransition(
            state: state,
            child: const TagAdd(),
          ),
        ),
        GoRoute(
          path: ':id',
          pageBuilder: (context, state) {
            final id = int.parse(state.pathParameters['id']!);
            return _buildPageWithSlideTransition(
              state: state,
              child: TagView(tagId: id),
            );
          },
        ),
      ],
    ),
    // --- Images ---
    GoRoute(
      path: '/images',
      pageBuilder: (context, state) =>
          _buildPageWithFadeTransition(state: state, child: const ImagesView()),
      routes: [
        GoRoute(
          path: 'view',
          pageBuilder: (context, state) {
            final extra = state.extra as Map<String, dynamic>;
            final assets = extra['assets'] as List<AssetEntity>;
            final initialIndex = extra['initialIndex'] as int;
            return _buildPageWithSlideTransition(
              state: state,
              child: ImageView(assets: assets, initialIndex: initialIndex),
            );
          },
        ),
        GoRoute(
          path: 'selected',
          pageBuilder: (context, state) => _buildPageWithSlideTransition(
            state: state,
            child: const ImagesSelectedView(),
          ),
        ),
      ],
    ),
  ],
);
