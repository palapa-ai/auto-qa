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
3. **Automated publishing (recommended).** This repo ships two workflows:
   [`tag-release.yml`](.github/workflows/tag-release.yml) — on a version bump to
   `main`, reads the version from `pubspec.yaml` and pushes the matching
   `vX.Y.Z` tag — and [`publish.yml`](.github/workflows/publish.yml) — on that
   tag, verifies the version + that the commit is on `main`, runs
   format/analyze/test, then publishes via tokenless GitHub OIDC. To enable it:
   - After the first manual publish, on the package's pub.dev admin page enable
     *Automated publishing → GitHub Actions*, repo `palapa-ai/auto_qa`, tag
     pattern `v{{version}}`.
   - Add a repo secret **`RELEASE_TAG_PAT`** — a fine-grained PAT with
     `contents: write` on `palapa-ai/auto_qa`. `tag-release.yml` pushes the tag
     with it so the tag event triggers `publish.yml` (tags pushed with the
     default `GITHUB_TOKEN` don't trigger other workflows). Only tag-pushing
     uses this PAT; publishing stays tokenless.

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

### Cut a release (bump + merge — no tagging by hand)

The version lives only in `pubspec.yaml`. Once automated publishing is enabled
(see one-time setup), to release you:

1. Bump `version:` in `pubspec.yaml`, the `autoQaServerVersion` constant in
   `lib/src/mcp_protocol.dart`, and add a matching `## X.Y.Z` heading to
   `CHANGELOG.md` (all three must match — the workflows enforce it).
2. Merge that to `main`.

That's it. `tag-release.yml` reads the version from `pubspec.yaml`, pushes the
`vX.Y.Z` tag, and `publish.yml` verifies + tests + publishes via OIDC. **You
never type a version into a release command, and there's no manual
`dart pub publish`.** (You can still push a `vX.Y.Z` tag by hand if you ever want
to — `publish.yml` handles that too.)

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
