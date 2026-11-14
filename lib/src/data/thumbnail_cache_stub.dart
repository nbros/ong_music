import 'package:flutter/painting.dart';

import 'thumbnail_cache.dart';

/// The web (and platforms with neither `dart:io` nor a browser): the plain
/// [NetworkImage], kept by the browser's HTTP cache.
ThumbnailImages createPlatformThumbnailImages() => (image: NetworkImage.new, dispose: () {});
