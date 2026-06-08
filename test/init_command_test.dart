// Unit tests for the pure content builders behind `auto_qa init`. The file I/O
// in `runInit` is exercised manually; the string builders carry the logic and
// are tested here.
import 'dart:convert';

import 'package:auto_qa/auto_qa.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('autoQaMcpJson', () {
    test('creates a fresh config registering the auto-qa server', () {
      final json = jsonDecode(autoQaMcpJson(null)) as Map<String, dynamic>;
      final servers = json['mcpServers'] as Map<String, dynamic>;
      final server = servers['auto-qa'] as Map<String, dynamic>;
      expect(server['command'], 'dart');
      expect(server['args'], containsAll(['run', 'auto_qa', '--launch']));
      expect(server['args'], contains('--device=macos'));
    });

    test('honours the device override', () {
      final json = jsonDecode(autoQaMcpJson(null, device: 'chrome'))
          as Map<String, dynamic>;
      final server =
          (json['mcpServers'] as Map)['auto-qa'] as Map<String, dynamic>;
      expect(server['args'], contains('--device=chrome'));
    });

    test('preserves other servers and top-level keys when merging', () {
      const existing = '''
{
  "someOtherKey": 1,
  "mcpServers": {
    "other": {"command": "x", "args": []}
  }
}
''';
      final json = jsonDecode(autoQaMcpJson(existing)) as Map<String, dynamic>;
      expect(json['someOtherKey'], 1);
      final servers = json['mcpServers'] as Map<String, dynamic>;
      expect(servers.keys, containsAll(['other', 'auto-qa']));
    });

    test('empty/whitespace existing is treated as a fresh file', () {
      expect(
        () => autoQaMcpJson('   '),
        returnsNormally,
      );
    });

    test('invalid JSON throws FormatException', () {
      expect(() => autoQaMcpJson('{not json'), throwsFormatException);
    });
  });

  group('driverEntrypoint', () {
    test('imports the given package and enables the driver extension', () {
      final src = driverEntrypoint('my_app');
      expect(src, contains("import 'package:my_app/main.dart' as app;"));
      expect(src, contains('enableFlutterDriverExtension();'));
      expect(src, contains('app.main();'));
    });
  });

  group('autoQaSkillMarkdown', () {
    test('has the auto-qa frontmatter name and references the MCP tools', () {
      final md = autoQaSkillMarkdown();
      expect(md, startsWith('---\nname: auto-qa\n'));
      expect(md, contains('mcp__auto-qa__screenshot'));
      expect(md, contains('mcp__auto-qa__tap'));
    });
  });
}
