# Contributing to auto-qa

Thanks for your interest! auto-qa is intentionally small and focused: a stdio
MCP server that drives a live Flutter app via `flutter_driver`. Contributions
that keep it small, dependency-light, and well-tested are very welcome.

## Development setup

```sh
git clone https://github.com/palapa-ai/auto-qa.git
cd auto-qa
flutter pub get
flutter test       # the protocol/options layer is fully unit-tested
flutter analyze
dart format .
```

To exercise it end to end, drive the bundled example app:

```sh
cd example && flutter pub get
# then register example/.mcp.json in your MCP client and ask it to drive the app
```

## Project layout

| Path | What |
|------|------|
| `lib/src/mcp_protocol.dart` | Pure protocol + option parsing — **no `flutter_driver` import**, so it's unit-testable. Put new pure logic here. |
| `lib/src/auto_qa_server.dart` | The `FlutterDriver`-backed I/O loop and tool implementations. |
| `bin/auto_qa.dart` | Executable entrypoint. |
| `test/` | Unit tests for the pure layer. |
| `example/` | A runnable app + driver entrypoint + `.mcp.json`. |

**Keep the pure/impure split.** Anything that doesn't need a live driver
connection belongs in `mcp_protocol.dart` so it stays under test.

**Stay dependency-light.** The JSON-RPC handling is hand-rolled on purpose
(no MCP framework dependency). Prefer the same approach for new work.

## Before opening a PR

1. `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, and
   `flutter test` all pass (CI runs exactly these).
2. Add a `CHANGELOG.md` entry for any user-facing change.
3. Update the README if you add/change a flag or tool.
4. Fill out the PR template.

## Filing issues

Use the **Bug report** or **Feature request** templates. For bugs, include the
`[auto-qa]` stderr lines and your `flutter --version`.

## Releasing

Maintainers: see [`RELEASING.md`](RELEASING.md) for the publish checklist.

## License

By contributing, you agree your contributions are licensed under the project's
[BSD-3-Clause license](LICENSE).
