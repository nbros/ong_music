/// The images of the YouTube thumbnails, kept on disk in the native apps.
///
/// Flutter keeps a [NetworkImage] only in memory: without a cache of our own,
/// the native apps download every thumbnail again each time they start. On
/// the web the browser's HTTP cache already keeps them, so the web build uses
/// [NetworkImage] as it is (and never loads `dart:io`).
library;

import 'package:flutter/painting.dart';

import 'thumbnail_cache_stub.dart' if (dart.library.io) 'thumbnail_cache_io.dart' as platform;

/// How the thumbnails of a run of the app are built, and how to release what
/// they hold (the HTTP client of the disk cache) when the app goes.
typedef ThumbnailImages = ({ImageProvider Function(String url) image, void Function() dispose});

/// The thumbnails of this platform: [NetworkImage] on the web (and on
/// platforms with neither `dart:io` nor a browser); on IO platforms, images
/// kept in the `thumbnails` directory of the application cache directory,
/// which the system may empty and which is not backed up.
///
/// Nothing is read or created before the first image is resolved.
ThumbnailImages createThumbnailImages() => platform.createPlatformThumbnailImages();
