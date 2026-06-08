// Executable entrypoint. With no args (or server flags) it runs the auto-qa MCP
// server — wire it into your MCP client's `.mcp.json` as `dart run auto_qa …`.
// `dart run auto_qa init` instead scaffolds the Claude Code wiring into the
// current project. See the README.
import 'package:auto_qa/auto_qa.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == 'init') {
    await runInit(args.skip(1).toList());
    return;
  }
  final opts = AutoQaOptions.parse(args);
  await AutoQaServer(opts).serve();
}
