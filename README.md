# auto-qa

[![pub package](https://img.shields.io/pub/v/auto_qa.svg)](https://pub.dev/packages/auto_qa)
[![CI](https://github.com/palapa-ai/auto-qa/actions/workflows/ci.yaml/badge.svg)](https://github.com/palapa-ai/auto-qa/actions/workflows/ci.yaml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

**Let an LLM drive your live Flutter app.** auto-qa is a small
[Model Context Protocol](https://modelcontextprotocol.io) (MCP) server that
exposes a running Flutter app as a handful of tools an AI agent can call —
`screenshot`, `tap`, `enter_text`, `scroll`, `wait_for`, `describe`. Point an
MCP client like [Claude Code](https://claude.com/claude-code) at it and the
agent can navigate your app, read each screen, and report bugs and rough edges
— hands-free QA.

It's a thin wrapper over Flutter's own
[`flutter_driver`](https://api.flutter.dev/flutter/flutter_driver/flutter_driver-library.html):
no backend, no cloud, no database — just a stdio process that holds one
`FlutterDriver` connection to your app.

> On pub.dev the package is published as **`auto_qa`** (Dart package names can't
> contain hyphens), so the dependency, `dart run auto_qa`, and imports use the
> underscore. Everywhere else — the project, repo, and MCP server — it's
> **auto-qa**.

## How it works

```
┌──────────────┐   MCP over stdio    ┌────────────┐   Dart VM Service   ┌───────────────┐
│  MCP client  │  (JSON-RPC 2.0)     │  auto-qa   │  (flutter_driver)   │  your Flutter │
│ (Claude Code)│ ◀─────────────────▶ │ MCP server │ ◀─────────────────▶ │      app      │
└──────────────┘                     └────────────┘                     └───────────────┘
```

The agent calls a tool (e.g. `tap(text: "Settings")`); auto-qa translates it
into a `flutter_driver` command against the app's VM Service and streams back
the result (text, or a PNG for `screenshot`).

There's nothing to host or deploy: a stdio MCP server is a **local subprocess
the client launches for you** and kills when the session ends — not a service
you run. See [What "server" means here](#what-server-means-here).

## Requirements

- The **Flutter SDK** (this is a Flutter package — `flutter_driver` ships with
  it).
- A **driver-enabled entrypoint** in your app (one line: `enableFlutterDriverExtension()`
  — see below).
- An **MCP client** (e.g. Claude Code).

## Setup

### Quick start: `auto_qa init` (recommended)

1. Add the dev dependency and fetch it:

   ```yaml
   dev_dependencies:
     auto_qa: ^0.1.0
   ```

   ```sh
   flutter pub get
   ```

2. Scaffold the Claude Code wiring with one command, from your project root:

   ```sh
   dart run auto_qa init
   ```

   It writes (and tells you what it did):
   - **`.mcp.json`** — registers the auto-qa MCP server (merged in if the file
     already exists; other servers are preserved).
   - **`.claude/skills/auto-qa/SKILL.md`** — an `/auto-qa` skill telling the
     agent how to drive your app.
   - **`test_driver/app.dart`** — a driver-enabled entrypoint importing your
     app's `main.dart` (skipped if it already exists).

   Flags: `--device=NAME` (default `macos`, e.g. `--device=chrome`) and
   `--force` (overwrite the skill / entrypoint).

3. Open Claude Code in the project and run **`/auto-qa`** (or just ask it to QA
   the app). Add `.auto-qa/` to your `.gitignore` — that's where screenshots
   land.

> `dart run auto_qa init` scaffolds files into *your* project because Claude
> Code discovers skills from `.claude/skills/`. Installing the pub package alone
> does **not** register a skill — pub has no post-install hook. A one-command
> Claude Code **plugin** (skill + MCP server in a single `/plugin install`) is
> planned; see the repo issues.

### Manual setup

Prefer to wire it up by hand? These steps are exactly what `dart run auto_qa
init` automates.

#### 1. Add the dependency

```yaml
dev_dependencies:
  auto_qa: ^0.1.0
```

```sh
flutter pub get
```

#### 2. Add a driver-enabled entrypoint

Create `test_driver/app.dart` that turns on the driver extension and then runs
your app:

```dart
import 'package:flutter_driver/driver_extension.dart';
import 'package:your_app/main.dart' as app;

void main() {
  enableFlutterDriverExtension();
  app.main();
}
```

> This entrypoint is for testing only — `flutter_driver` never reaches your
> production build. See [`example/`](example/) for a copyable version.

#### 3. Register the MCP server

For Claude Code, add a `.mcp.json` at your project root:

```json
{
  "mcpServers": {
    "auto-qa": {
      "command": "dart",
      "args": [
        "run",
        "auto_qa",
        "--launch",
        "--device=macos",
        "--target=test_driver/app.dart",
        "--artifacts=.auto-qa/shots"
      ]
    }
  }
}
```

The server key is `auto-qa` (so its tools are `mcp__auto-qa__…`); the command
runs the `auto_qa` executable (the pub package). Start your MCP client and ask
the agent to drive the app — e.g. *"Open the app, walk through every screen, and
list anything that looks broken or off."*

## What "server" means here

auto-qa uses MCP's **stdio** transport, so "server" does **not** mean a hosted
service:

- You don't start it, leave it running, open a port, or deploy anything.
- You just declare it in `.mcp.json`. When your MCP client starts, it **spawns
  `dart run auto_qa …` as a child process**, pipes JSON-RPC over stdin/stdout,
  and **kills it when the session ends**.
- The only processes that ever run are that short-lived subprocess and the
  Flutter app it launches — both gone when you quit.

(Reaching auto-qa from another machine — e.g. CI driving the app, agent
elsewhere — would mean adding MCP's HTTP transport and actually hosting it.
That's out of scope; stdio is the right default.)

## Connection modes

auto-qa reaches your app one of two ways (the connection is lazy — made on the
first tool call, so the MCP handshake never blocks on a build):

| Mode | Flag | What it does |
|------|------|--------------|
| **Launch** | `--launch` | Spawns `flutter run --target=<target>` itself, parses the VM Service URI, and owns the app's lifecycle (kills it on shutdown). |
| **Attach** | `--vm-service-uri=URI` | Connects to an app you already started with `flutter run` (copy the *Dart VM Service* URI it prints). |

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--launch` | off | Launch the app instead of attaching. |
| `--vm-service-uri=URI` | — | Attach to an already-running app at this URI. |
| `--device=NAME` | `macos` | Flutter device id for launch mode (`macos`, `chrome`, a device id…). |
| `--target=PATH` | `test_driver/app.dart` | Driver-enabled entrypoint to launch. |
| `--dart-define=K=V` | — | Forwarded to `flutter run` (repeatable). |
| `--defines-file=PATH` | — | JSON array of `--dart-define=…` strings (for many defines). |
| `--tap-key=KEY` | — | After connecting, tap the widget with this `ValueKey` (e.g. dismiss a splash / sign in). |
| `--ready-delay-ms=N` | `0` | Wait N ms after connect before the first interaction (apps with async startup). Prefer `wait_for`. |
| `--artifacts=DIR` | temp dir | Where `screenshot` writes PNGs. |

## Tools

| Tool | Args | Returns |
|------|------|---------|
| `screenshot` | `label?` | A PNG of the current screen (inline image + saved path). Your primary way to *see* the app. |
| `describe` | — | The render tree as text. Useful to discover exact widget keys/labels. |
| `tap` | one of `text` / `key` / `tooltip` | Taps the matching widget. |
| `enter_text` | `text`, `focus_text?` / `focus_key?` | Types into the focused field (optionally tapping it first). |
| `scroll` | `text?` / `key?`, `dx?`, `dy?`, `duration_ms?` | Scrolls a scrollable (or the screen). Negative `dy` scrolls down. |
| `wait_for` | one of `text` / `key` / `tooltip`, `timeout_s?`, `absent?` | Waits for a widget to be present/absent. Returns `present` / `absent` / `timeout`. |

## Notes

- **`runUnsynchronized` is built in.** Continuously-animating apps never go
  frame-idle, which would hang the default `flutter_driver` sync. auto-qa
  wraps every interaction in `runUnsynchronized`, so animated UIs just work.
- **Finders are semantic.** Target widgets by visible text, `ValueKey`, or
  tooltip. Adding `ValueKey`s to important widgets makes the agent more
  reliable.
- **stdout is the protocol.** All diagnostics go to stderr; the MCP client only
  sees clean JSON-RPC on stdout.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and
feature requests have [issue templates](.github/ISSUE_TEMPLATE), and every PR
runs format + analyze + test in CI.

## License

BSD-3-Clause © Palapa AI. See [LICENSE](LICENSE).
