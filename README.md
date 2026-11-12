# Ong Music

The Android version of this app is available on the Google Play Store: <br/>
https://play.google.com/store/apps/details?id=nbros.ong_music

The Windows version can be downloaded directly from this page and unzipped:<br/>
https://github.com/nbros/ong_music/releases/latest

The web version runs in any browser, and is the way to use Ong Music on iPhone and iPad:<br/>
https://nbros.github.io/ong_music/app/<br/>
To install it on iPhone/iPad: open that link in Safari, tap Share (on recent iOS versions it is behind the menu
button next to the address, then "View More"), then "Add to Home Screen". The page shows these steps too.


[![](https://img.shields.io/badge/Made%20With%20Flutter-blue)](https://flutter.dev/)

[![Flutter CI/CD](https://github.com/nbros/ong_music/actions/workflows/flutter_ci.yml/badge.svg)](https://github.com/nbros/ong_music/actions/workflows/flutter_ci.yml)
[![GitHub Pages](https://github.com/nbros/ong_music/actions/workflows/pages.yml/badge.svg)](https://github.com/nbros/ong_music/actions/workflows/pages.yml)

## Development

Use the Flutter version pinned by `FLUTTER_VERSION` in [`.github/workflows/flutter_ci.yml`](.github/workflows/flutter_ci.yml)
(and in [`pages.yml`](.github/workflows/pages.yml): bump both together).

```sh
flutter pub get
flutter analyze
flutter test

# The app shows the version given by APP_VERSION (optional for local builds).
flutter build appbundle --dart-define=APP_VERSION=1.6.0   # Android (release signing needs android/key.properties)
flutter build windows --release --dart-define=APP_VERSION=1.6.0
flutter build web --release --base-href /ong_music/app/ --no-web-resources-cdn --web-content-hash --dart-define=APP_VERSION=1.6.0   # output in build/web
```

To try the web app locally: `flutter run -d chrome`. A `build/web` built with `--base-href /ong_music/app/` only works
when served under `/ong_music/app/`.

### Releases

Every push to `master` runs [Flutter CI/CD](.github/workflows/flutter_ci.yml): analyze, tests, Android and Windows builds
(kept as workflow artifacts), without publishing anything.

To release, push an annotated tag named after the version; the tag message becomes the GitHub release notes:

```sh
git tag -a 1.6.0 -m "What changed in 1.6.0"
git push origin 1.6.0
```

The tag triggers:
- [Flutter CI/CD](.github/workflows/flutter_ci.yml): upload to the Google Play **alpha** track,
  and a [GitHub release](https://github.com/nbros/ong_music/releases) with the Windows zip;
- [GitHub Pages](.github/workflows/pages.yml): deployment of the web app to https://nbros.github.io/ong_music/app/,
  together with the pages in [`docs/`](docs) at https://nbros.github.io/ong_music/ (home page and privacy policy).

The site is only deployed by that workflow: a change to `docs/` pushed to `master` goes online with the next tag, or
right away with a manual run (Actions → GitHub Pages → Run workflow, on `master`). A manual run is also the way to try the
web app on a real iPhone before tagging. The two workflows are independent: a Pages failure does not affect the
Play Store and Windows release, and vice versa.

### GitHub Pages settings

The Pages workflow needs two repository settings, both in place since November 2026 (kept here in case the
repository is recreated or forked):

1. Settings → Pages → Build and deployment → Source: **GitHub Actions** (not "Deploy from a branch"). To check:
   ```sh
   gh api repos/nbros/ong_music/pages --jq .build_type   # workflow
   ```
2. Settings → Environments → `github-pages` → Deployment branches and tags: `master` and a **tag rule** `*`
   (without it a tag-triggered deployment is rejected). To check:
   ```sh
   gh api repos/nbros/ong_music/environments/github-pages/deployment-branch-policies --jq '.branch_policies[].name'
   ```

After the first run of the workflow (Actions → GitHub Pages → Run workflow on `master`), check
https://nbros.github.io/ong_music/, https://nbros.github.io/ong_music/privacy-policy and
https://nbros.github.io/ong_music/app/. Until that first run, the site keeps serving the last deployment of the old
"Deploy from a branch" build.
