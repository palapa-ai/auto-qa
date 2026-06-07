/// auto_qa — an MCP server that lets an LLM drive a live Flutter app.
///
/// Drive any driver-enabled Flutter app over the Dart VM Service and expose it
/// to an MCP client (e.g. Claude Code) as a set of tools — screenshot, tap,
/// type, scroll, wait, and describe — for AI-assisted QA.
///
/// Most users run this as the `auto_qa` executable (see the package README) and
/// never import the library. It's exported here so the server can also be
/// embedded or extended programmatically.
library;

export 'src/auto_qa_server.dart';
export 'src/init_command.dart';
export 'src/mcp_protocol.dart';
