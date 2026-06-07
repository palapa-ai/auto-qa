## 0.1.0

Initial release.

- MCP server (stdio, JSON-RPC 2.0) that drives a live Flutter app via
  `flutter_driver`.
- Tools: `screenshot`, `describe`, `tap`, `enter_text`, `scroll`, `wait_for`.
- **Launch** mode (spawns `flutter run` and owns the app's lifecycle) and
  **attach** mode (`--vm-service-uri`).
- Pass-through `--dart-define=` flags and `--defines-file`, plus `--tap-key`
  and `--ready-delay-ms` for apps with a splash / async startup.
- Every interaction wrapped in `runUnsynchronized` so continuously-animating
  apps don't hang.
