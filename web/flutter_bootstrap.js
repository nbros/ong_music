{{flutter_js}}
// The build config ends with the feature test of the WebAssembly build, which throws in a browser without
// WebAssembly at all (JavaScript JIT turned off: iOS Lockdown Mode, some company policies). Neither build runs there
// (CanvasKit is WebAssembly too): the loader then fails below, and the loading screen shows its error at once
// (the one of a failed download), instead of "Still loading…" after 20 seconds.
try {
{{flutter_build_config}}
} catch (e) {}

// Loaded by index.html. Template filled by `flutter build web` (see https://docs.flutter.dev/platform-integration/web/initialization).
//
// The site holds two builds of the app (`flutter build web --wasm`): WebAssembly (main.dart.<hash>.wasm and .mjs,
// drawn by Skwasm) and JavaScript (main.dart.<hash>.js, drawn by CanvasKit). The loader picks the first one the
// browser can run: WebAssembly in Chromium browsers recent enough (WasmGC and the rest, WebGL), JavaScript in every
// other one (Safari, Firefox, older Chromium, Edge with its enhanced security on).
(function () {
  // The engine files (canvaskit/: CanvasKit and Skwasm, built with --no-web-resources-cdn) keep the same names from
  // one Flutter version to the next, unlike main.dart.<hash>.*. After a deployment that changes the engine, make sure
  // the browser does not reuse engine files from its cache (GitHub Pages: up to 10 minutes) with the new app: the
  // files the loader is about to use are revalidated. Costs nothing otherwise.
  // Not covered: a browser that changes build (WebGL lost, a security mode switched) within those 10 minutes, after
  // the other build has stored the new revision, may run once with an engine file of the previous version.
  var key = 'ongMusic.engineRevision';
  var revision = _flutter.buildConfig.engineRevision;
  var previous = null;
  try { previous = localStorage.getItem(key); } catch (e) {}
  var ready = Promise.resolve();
  if (previous && previous !== revision) {
    // The .wasm files: the loader fetches the one of the build it chose, revalidated here (not before: which build
    // the loader chooses is known to it alone).
    var engine = new URL('canvaskit/', document.baseURI).href;
    var fetch0 = window.fetch;
    window.fetch = function (input, init) {
      if (typeof input === 'string' && input.indexOf(engine) === 0 && init === undefined) {
        return fetch0.call(window, input, { cache: 'no-cache' });
      }
      return fetch0.apply(window, arguments);
    };
    window.addEventListener('flutter-first-frame', function () { window.fetch = fetch0; });
    // The JavaScript of the engine, which the loader imports as a module (no cache option there): revalidated before
    // the loader starts, for both builds this browser may get (small files). Same choice of variant as the loader:
    // the "chromium" ones where the browser decodes images and breaks text itself, the full ones elsewhere; Skwasm
    // only in Chromium browsers (the others get the JavaScript build).
    var blink = navigator.vendor === 'Google Inc.' || navigator.userAgent.indexOf('Edg/') >= 0;
    var chromium = blink && typeof ImageDecoder !== 'undefined' && typeof Intl.v8BreakIterator !== 'undefined' &&
      typeof Intl.Segmenter !== 'undefined';
    var scripts = [chromium ? 'canvaskit/chromium/canvaskit.js' : 'canvaskit/canvaskit.js'];
    if (blink) scripts.push(chromium ? 'canvaskit/skwasm.js' : 'canvaskit/skwasm_heavy.js');
    ready = Promise.all(scripts.map(function (url) {
      return fetch0.call(window, url, { cache: 'no-cache' }).then(function (r) { return r.arrayBuffer(); });
    })).catch(function () {});
  }
  window.addEventListener('flutter-first-frame', function () {
    try { localStorage.setItem(key, revision); } catch (e) {}
  });
  // A failure of the engine start (CanvasKit or Skwasm missing or cut short) goes to the loading screen of
  // index.html, which offers to reload; the loader would only leave it in the console.
  function failed(e) {
    console.error('Ong Music could not start', e);
    if (window.ongMusicLoadFailed) window.ongMusicLoadFailed();
  }
  var config = {
    // GitHub Pages cannot send the headers that would let Skwasm draw on other threads (COOP and COEP, which would
    // also keep YouTube's player out of the page): it draws on the page's thread, as CanvasKit does. Said once here
    // rather than at every start in the console.
    suppressMultithreadingWarning: true,
  };
  // No service worker: Flutter's is deprecated (it now only unregisters itself), and the HTTP cache is enough.
  ready.then(function () {
    return _flutter.loader.load({
      config: config,
      onEntrypointLoaded: function (engineInitializer) {
        return engineInitializer.initializeEngine(config).then(function (appRunner) {
          return appRunner.runApp();
        }).catch(failed);
      },
    });
  }).catch(failed);
})();
