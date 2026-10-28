import 'package:career_pocket/core/api/sse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses events, multi-line data and skips comments', () async {
    final lines = Stream.fromIterable(['event: delta', 'data: {"text":"Hi"}', '', ': keep-alive', '', 'event: done', 'data: a', 'data: b', '']);
    final events = await parseSse(lines).toList();
    expect(events.length, 2);
    expect(events[0].event, 'delta');
    expect(events[0].json['text'], 'Hi');
    expect(events[1].data, 'a\nb');
  });
}
