# auto_qa example

A tiny, runnable Flutter app (`lib/main.dart`) plus the two pieces you need to
drive it with `auto_qa`.

- [`lib/main.dart`](lib/main.dart) — a one-screen counter app. Its widgets have
  stable `ValueKey`s (`increment`, `count`) and visible text so the agent can
  target them.
- [`test_driver/app.dart`](test_driver/app.dart) — the driver-enabled
  entrypoint. Copy this into your own app's `test_driver/` directory and change
  the import to your package's `main.dart`.
- [`.mcp.json`](.mcp.json) — an MCP server registration (e.g. for Claude Code).
  Drop it at your project root.

## Try it

```sh
flutter pub get
```

Then start your MCP client in this directory and ask the agent to drive the app,
e.g.:

> Open the app, read the count, tap the increment button three times, and
> confirm the count is 3.

Under the hood the agent will call `tap(key: "increment")` and
`wait_for(text: "Count: 3")` against the running app.

See the [package README](../README.md) for the full option and tool reference.
