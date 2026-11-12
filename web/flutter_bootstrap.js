{{flutter_js}}
{{flutter_build_config}}

// Loaded by index.html. Template filled by `flutter build web` (see https://docs.flutter.dev/platform-integration/web/initialization).
(function () {
  // CanvasKit (canvaskit/, built with --no-web-resources-cdn) keeps the same file names from one Flutter
  // version to the next, unlike main.dart.<hash>.js. After a deployment that changes the engine, make sure
  // the browser does not reuse a CanvasKit from its cache (GitHub Pages: up to 10 minutes) with the new
  // main.dart.js: revalidate the files the loader is about to use. Costs nothing otherwise.
  var key = 'ongMusic.engineRevision';
  var revision = _flutter.buildConfig.engineRevision;
  var previous = null;
  try { previous = localStorage.getItem(key); } catch (e) {}
  var ready = Promise.resolve();
  if (previous && previous !== revision) {
    // same choice as the loader: the "chromium" variant on Chromium browsers, the full one elsewhere
    var chromium = typeof Intl.v8BreakIterator !== 'undefined' && typeof ImageDecoder !== 'undefined' &&
      (navigator.vendor === 'Google Inc.' || navigator.userAgent.indexOf('Edg/') >= 0);
    var dir = chromium ? 'canvaskit/chromium/' : 'canvaskit/';
    ready = Promise.all([dir + 'canvaskit.js', dir + 'canvaskit.wasm'].map(function (url) {
      return fetch(url, { cache: 'no-cache' }).then(function (r) { return r.arrayBuffer(); });
    })).catch(function () {});
  }
  window.addEventListener('flutter-first-frame', function () {
    try { localStorage.setItem(key, revision); } catch (e) {}
  });
  // No service worker: Flutter's is deprecated (it now only unregisters itself), and the HTTP cache is enough.
  ready.then(function () { _flutter.loader.load(); });
})();
