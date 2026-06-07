# Releasing auto_qa to pub.dev

A checklist for cutting a release. The first publish establishes the package
name on [pub.dev](https://pub.dev) and ties it to a publisher/account.

## One-time setup

1. **pub.dev account.** Sign in at <https://pub.dev> with a Google account. The
   first `dart pub publish` from a machine opens a browser to authorize it.
2. **(Recommended) Verified publisher.** Create a verified publisher for a
   domain you control (e.g. `palapa.ai`) at
   <https://pub.dev/create-publisher>. Publishing under a verified publisher
   shows the domain on the package page and is the norm for org-owned packages.
   Optional — you can publish under your account first and migrate later.
3. **Automated publishing (optional, recommended).** pub.dev supports
   publishing straight from GitHub Actions on a version tag, with no long-lived
   token. On the package's pub.dev admin page, enable
   *Automated publishing → GitHub Actions*, set the repo to
   `palapa-ai/auto-qa` and a tag pattern like `v{{version}}`, then add the
   official workflow (`dart-lang/setup-dart/.github/workflows/publish.yml`).
   Once enabled, releasing is just: tag `vX.Y.Z` and push.

## Pre-flight (every release)

Run from the package root:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .   # formatting clean
flutter analyze                                       # no analyzer issues
flutter test                                          # protocol tests green
dart pub publish --dry-run                            # packaging + score check
```

`--dry-run` validates the package layout, the `pubspec.yaml`, the presence of
`LICENSE` / `README.md` / `CHANGELOG.md`, and surfaces anything that would cost
pub.dev score points. Fix every warning before a real publish.

Also confirm:

- [ ] `version:` in `pubspec.yaml` is bumped and matches the top `CHANGELOG.md`
      entry.
- [ ] `autoQaServerVersion` in `lib/src/mcp_protocol.dart` matches `version:`.
- [ ] `README.md` examples still reflect the current flags/tools.
- [ ] `repository:` / `issue_tracker:` URLs are correct.

## Publish

### Manual

```sh
dart pub publish
```

Review the file list it prints, then confirm. **This is irreversible** — a
published version can be *retracted* but never overwritten or deleted, and the
package name is permanent.

### Tag the release

```sh
git tag v0.1.0
git push origin v0.1.0
```

(If automated publishing is enabled, pushing the tag *is* the publish step —
skip the manual `dart pub publish`.)

Then cut a GitHub Release from the tag with the changelog notes.

## After publishing

- Check the package page and its **pub points** at
  `https://pub.dev/packages/auto_qa/score`; address any deductions
  (documentation, platform support, up-to-date deps) in the next release.
- For the next version: add a new `## X.Y.Z` section to `CHANGELOG.md`, bump
  `version:` (and `autoQaServerVersion`), and repeat the pre-flight.

## Versioning

Follow [semver](https://semver.org): `0.x` while the API/flags may still
change; bump the minor for new features, the patch for fixes. Move to `1.0.0`
once the tool set and flags are stable.
