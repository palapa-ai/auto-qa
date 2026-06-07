// Executable entrypoint for the auto_qa MCP server. Wire it into your MCP
// client (e.g. a project `.mcp.json`) as `dart run auto_qa …` — see the README.
import 'package:auto_qa/auto_qa.dart';

Future<void> main(List<String> args) async {
  final opts = AutoQaOptions.parse(args);
  await AutoQaServer(opts).serve();
}
