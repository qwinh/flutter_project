# Flutter Album Manager App — Implementation Plan

A Flutter mobile app for managing photo albums with tags, built around an SQLite local database. Users browse system images, pick them into a persistent selection, then commit selections to albums. Albums and tags provide organization and filtering.

## User Review Required

> [!IMPORTANT]
> **Image access library choice**: We'll use `photo_manager` to access device photos. This requires Android/iOS permissions. Confirm this is acceptable.

> [!IMPORTANT]
> **Notifications**: The rubric requires local notifications. Plan: notify when an album is created/modified. Will use `flutter_local_notifications`. Confirm or suggest alternative trigger.

> [!IMPORTANT]
> **Deployment**: Rubric asks for real-device deploy. We'll prepare a release APK. You'll need a connected device or emulator to verify.

---

## Proposed Changes

### Project Initialization

#### [NEW] Flutter project scaffold

```
flutter create --org com.example --project-name album_manager .
```

**Dependencies** (`pubspec.yaml`):
- `go_router` — routing
- `provider` — state management
- `sqflite` — SQLite
- `path` — DB path helper
- `photo_manager` — device gallery access
- `flutter_local_notifications` — notifications
- `intl` — date formatting

---

### Database Layer

#### [NEW] [db_helper.dart](file:///e:/github/testing/lib/services/db_helper.dart)

SQLite open/create with migration support. Tables:

```sql
CREATE TABLE albums (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT DEFAULT '',
  favorite INTEGER DEFAULT 0,
  date_created TEXT NOT NULL,
  date_latest_modify TEXT NOT NULL
);

CREATE TABLE tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT DEFAULT ''
);

CREATE TABLE tags_albums (
  album_id INTEGER NOT NULL,
  tag_id INTEGER NOT NULL,
  PRIMARY KEY (album_id, tag_id),
  FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

CREATE TABLE albums_images (
  album_id INTEGER NOT NULL,
  image_uri TEXT NOT NULL,
  PRIMARY KEY (album_id, image_uri),
  FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE
);

CREATE TABLE images_selected (
  image_uri TEXT PRIMARY KEY
);
```

#### [NEW] [album_service.dart](file:///e:/github/testing/lib/services/album_service.dart)

CRUD for albums: `getAll`, `getById`, `insert`, `update`, `delete`, `toggleFavorite`, `addImage`, `removeImage`, `getAlbumImages`, `getAlbumsByTag`.

#### [NEW] [tag_service.dart](file:///e:/github/testing/lib/services/tag_service.dart)

CRUD for tags + junction table: `getAll`, `getById`, `insert`, `update`, `delete`, `getTagsForAlbum`, `setTagsForAlbum`.

#### [NEW] [image_selection_service.dart](file:///e:/github/testing/lib/services/image_selection_service.dart)

Temp-selected images: `getAll`, `add`, `remove`, `clear`.

---

### Models

#### [NEW] [album.dart](file:///e:/github/testing/lib/models/album.dart)

```dart
class Album {
  final int? id;
  final String name, description;
  final bool favorite;
  final DateTime dateCreated, dateLatestModify;
  // fromMap, toMap
}
```

#### [NEW] [tag.dart](file:///e:/github/testing/lib/models/tag.dart)

```dart
class Tag {
  final int? id;
  final String name, description;
}
```

---

### State Management (ChangeNotifier + Provider)

#### [NEW] [album_manager.dart](file:///e:/github/testing/lib/managers/album_manager.dart)

Wraps `AlbumService`. Holds `List<Album>`, exposes add/edit/delete/filter/toggleFavorite. Calls `notifyListeners()`.

#### [NEW] [tag_manager.dart](file:///e:/github/testing/lib/managers/tag_manager.dart)

Wraps `TagService`. Holds `List<Tag>`, exposes add/edit/delete/filter.

#### [NEW] [image_selection_manager.dart](file:///e:/github/testing/lib/managers/image_selection_manager.dart)

Wraps `ImageSelectionService`. Holds `Set<String>` of selected URIs. Persisted to SQLite. Exposes add/remove/clear/commit-to-album.

---

### Routing

#### [NEW] [main.dart](file:///e:/github/testing/lib/main.dart)

- `MultiProvider` wrapping the app with all three managers.
- `GoRouter` with routes:

| Path | Screen | Notes |
|---|---|---|
| `/albums` | AlbumsView | Initial route |
| `/albums/add` | AlbumAdd | |
| `/albums/:id` | AlbumView | Edit album |
| `/tags` | TagsView | |
| `/tags/add` | TagAdd | |
| `/tags/:id` | TagView | Edit tag |
| `/images` | ImagesView | System gallery browser |
| `/images/view` | ImageView | Full-screen swipe viewer |
| `/images/selected` | ImagesSelectedView | Review & commit picks |

Custom slide transitions on push.

---

### UI Screens (≥ 6 pages, rubric requirement met with 10)

#### [NEW] [app_drawer.dart](file:///e:/github/testing/lib/uis/shared/app_drawer.dart)

Drawer with links: Albums, Tags, Browse Images, Selected Images. Uses `context.go()`.

#### [NEW] [albums_view.dart](file:///e:/github/testing/lib/uis/albums/albums_view.dart)

- `ListView` of album cards (name, image count, favorite star, date).
- Filter by name search, by tag, by favorite.
- Swipe-to-delete or long-press delete with confirmation.
- FAB → AlbumAdd.

#### [NEW] [album_view.dart](file:///e:/github/testing/lib/uis/albums/album_view.dart)

- `GridView` of album images.
- Edit name/description, manage tags (chip selector).
- Remove images.
- AppBar actions: edit, delete album.

#### [NEW] [album_add.dart](file:///e:/github/testing/lib/uis/albums/album_add.dart)

- Form: name, description.
- Tag selector (multi-select chips).
- Shows currently selected images count with option to go to ImagesSelectedView.
- Save → creates album, commits selected images, clears selection.

#### [NEW] [tags_view.dart](file:///e:/github/testing/lib/uis/tags/tags_view.dart)

- `ListView` of tags. Filter by name.
- Delete with confirmation.
- FAB → TagAdd.

#### [NEW] [tag_view.dart](file:///e:/github/testing/lib/uis/tags/tag_view.dart)

- Edit tag name/description.
- Shows albums using this tag.

#### [NEW] [tag_add.dart](file:///e:/github/testing/lib/uis/tags/tag_add.dart)

- Form: name, description. Save.

#### [NEW] [images_view.dart](file:///e:/github/testing/lib/uis/images/images_view.dart)

- Uses `photo_manager` to list device images in a `GridView`.
- Tap to select/deselect (adds to `images_selected`).
- Visual indicator (checkmark overlay) for selected images.
- Filter: by album (show only images in album / not in any album), by resolution.
- Efficient N·log(N) matching: load sorted image IDs from device, load sorted image URIs from DB, merge-compare.
- AppBar badge showing selected count → tap opens ImagesSelectedView.

#### [NEW] [image_view.dart](file:///e:/github/testing/lib/uis/images/image_view.dart)

- Full-screen image with `PageView` for swipe left/right navigation.
- Receives the image list + current index from prior context.
- Toggle select/deselect from here.

#### [NEW] [images_selected_view.dart](file:///e:/github/testing/lib/uis/images/images_selected_view.dart)

- `GridView` of currently selected images.
- Remove individual images.
- "Add More" button → back to ImagesView.
- "Commit to Album" → choose existing album or create new (→ AlbumAdd).
- "Clear All" with confirmation.

---

### Polish

#### App icon & splash

- Update `android/app/src/main/AndroidManifest.xml` app name.
- Use `flutter_launcher_icons` to set a custom icon.
- Use `flutter_native_splash` for splash screen.

#### Local Notifications

- `flutter_local_notifications` initialized in `main.dart`.
- Fire notification on album create/update.

#### Responsive Layout

- Use `LayoutBuilder`/`MediaQuery` so grid columns adapt (2 cols portrait, 3+ landscape/tablet).

---

## Verification Plan

### Automated Tests

Since this is a UI-heavy Flutter app, automated unit tests are not the primary verification method. However:

```bash
# Build verification — must compile without errors
flutter build apk --debug
```

### Manual Verification (step-by-step)

1. **Run the app**: `flutter run` on a connected device or emulator.
2. **Drawer navigation**: Open drawer → tap Albums, Tags, Browse Images, Selected. Confirm each navigates correctly.
3. **Create a tag**: Tags → FAB → fill name + description → Save. Confirm it appears in list.
4. **Edit a tag**: Tap tag → change name → Save. Confirm update.
5. **Delete a tag**: Long-press or swipe → confirm deletion. Confirm removed.
6. **Browse images**: Images → confirm device photos load in grid.
7. **Select images**: Tap images to select (checkmark appears). Badge counter updates.
8. **Persist selection**: Kill app → relaunch → go to Selected Images → confirm picks persist.
9. **Create album from selection**: Selected Images → "Commit to Album" → "New Album" → fill form → Save. Confirm album created with images.
10. **View album**: Albums → tap album → confirm images shown in grid.
11. **Filter albums by tag**: Albums → filter by tag → confirm filtering works.
12. **Swipe image viewer**: Album or Images → tap image → swipe left/right → confirm navigation.
13. **Notification**: After creating/editing album, confirm local notification appears.
14. **Responsive**: Rotate device → confirm grid adapts columns.
15. **Release build**: `flutter build apk --release` → install on device → confirm app name/icon/splash.
