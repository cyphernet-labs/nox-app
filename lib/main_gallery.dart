import 'package:flutter/material.dart';
import 'package:nox_app/gallery/gallery_app.dart';

/// Dev-only entry point for the UI-kit gallery:
///   fvm flutter run -t lib/main_gallery.dart
///
/// Intentionally separate from `lib/main.dart` so the gallery never ships in the
/// product app or release builds, and is unreachable from product navigation (FR-015).
void main() => runApp(const GalleryApp());
