# Ong Music

The Android version of this app is available on the Google Play Store: <br/>
https://play.google.com/store/apps/details?id=nbros.ong_music

The Windows version can be downloaded directly from this page and unzipped:<br/>
https://github.com/nbros/ong_music/releases/latest

The web version runs in any browser, and is the way to use Ong Music on iPhone and iPad:<br/>
https://ongmusic.nbros.dev/<br/>
To install it on iPhone/iPad: open that link in Safari, tap Share (on recent iOS versions it is behind the More or
menu button next to the address), then "Add to Home Screen" (under "View More" if it is not listed). The page shows the
steps for the Safari it runs in.


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
flutter build web --release --no-web-resources-cdn --web-content-hash --dart-define=APP_VERSION=1.6.0   # output in build/web
```

To try the web app locally: `flutter run -d chrome`. A `build/web` is made to be served at the root of a site
(`--base-href /`, the default).

### Releases

Every push to `master` runs [Flutter CI/CD](.github/workflows/flutter_ci.yml): analyze, tests, Android and Windows builds
(kept as workflow artifacts), without publishing anything.

To release, push an annotated tag named after the version, three plain numbers (`2.0.0`, not `v2.0.0` nor
`2.0.0-beta1`: the next builds of `master` compute their version from it, and the GitHub release of the tag becomes
"Latest"); the tag message becomes the GitHub release notes:

```sh
git tag -a 1.6.0 -m "What changed in 1.6.0"
git push origin 1.6.0
```

The tag triggers:
- [Flutter CI/CD](.github/workflows/flutter_ci.yml): upload to the Google Play **alpha** track,
  and a [GitHub release](https://github.com/nbros/ong_music/releases) with the Windows zip;
- [GitHub Pages](.github/workflows/pages.yml): deployment of the web app to https://ongmusic.nbros.dev/,
  together with the pages in [`docs/`](docs): https://ongmusic.nbros.dev/privacy-policy and
  https://ongmusic.nbros.dev/download.

If a job fails after the upload to Google Play succeeded, use **Re-run failed jobs**, never "Re-run all jobs": a
re-run keeps its run number, which is the Android version code, and Google Play refuses a version code twice. Do not
push two tags at once either: their two uploads to the same track could collide.

The upload has no release notes: type the "What's new" text in the Play Console when promoting the release from the
alpha (closed testing) track to production.

The site is only deployed by that workflow: a change to `docs/` pushed to `master` goes online with the next tag, or
right away with a manual run (Actions → GitHub Pages → Run workflow, on `master`). A manual run is also the way to try the
web app on a real iPhone before tagging. The two workflows are independent: a Pages failure does not affect the
Play Store and Windows release, and vice versa.

### GitHub Pages settings

The Pages workflow needs three settings (kept here in case the repository is recreated or forked):

1. Settings → Pages → Build and deployment → Source: **GitHub Actions** (not "Deploy from a branch"). To check:
   ```sh
   gh api repos/nbros/ong_music/pages --jq .build_type   # workflow
   ```
2. Settings → Environments → `github-pages` → Deployment branches and tags: `master` and a **tag rule** `*`
   (without it a tag-triggered deployment is rejected). To check:
   ```sh
   gh api repos/nbros/ong_music/environments/github-pages/deployment-branch-policies --jq '.branch_policies[].name'
   ```

3. The custom domain `ongmusic.nbros.dev`: at the registrar of `nbros.dev`, a DNS record `ongmusic` of type CNAME
   with the value `nbros.github.io`; then Settings → Pages → Custom domain: `ongmusic.nbros.dev`, and "Enforce HTTPS"
   once the certificate is issued. A deployment by workflow uses no `CNAME` file. To check:
   ```sh
   gh api repos/nbros/ong_music/pages --jq '.cname, .https_enforced'   # ongmusic.nbros.dev, true
   ```
   The web app keeps the favourites and the Twitch name per site address, and an iPhone installs it from that address:
   changing the domain later would lose both for everyone.

After the first run of the workflow (Actions → GitHub Pages → Run workflow on `master`), check
https://ongmusic.nbros.dev/ (the web app), https://ongmusic.nbros.dev/privacy-policy and
https://ongmusic.nbros.dev/download. Until that first run, the site keeps serving the last deployment of the old
"Deploy from a branch" build: its home page and the privacy policy.
