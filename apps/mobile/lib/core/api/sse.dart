import 'dart:convert';

class SseEvent {
  const SseEvent(this.event, this.data);
  final String event;
  final String data;

  Map<String, dynamic> get json {
    try {
      final v = jsonDecode(data);
      return v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  @override
  String toString() => 'SseEvent($event, $data)';
}

/// Parses a stream of text lines in the Server-Sent Events format.
Stream<SseEvent> parseSse(Stream<String> lines) async* {
  String? event;
  final data = StringBuffer();
  await for (final line in lines) {
    if (line.isEmpty) {
      if (event != null || data.isNotEmpty) yield SseEvent(event ?? 'message', data.toString());
      event = null;
      data.clear();
      continue;
    }
    if (line.startsWith(':')) continue;
    if (line.startsWith('event:')) {
      event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      if (data.isNotEmpty) data.write('\n');
      data.write(line.substring(5).trimLeft());
    }
  }
  if (event != null || data.isNotEmpty) yield SseEvent(event ?? 'message', data.toString());
}
