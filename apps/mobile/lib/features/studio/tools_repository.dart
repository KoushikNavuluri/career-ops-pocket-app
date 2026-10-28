import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/util/json.dart';

class ToolField {
  const ToolField({required this.key, required this.label, required this.kind, required this.required, this.minLength, this.maxLength, this.choices = const []});
  final String key;
  final String label;
  final String kind;
  final bool required;
  final int? minLength;
  final int? maxLength;
  final List<String> choices;
}

class WritingTool {
  const WritingTool({required this.id, required this.title, required this.description, required this.needsJob, required this.fields});
  final String id;
  final String title;
  final String description;
  final String needsJob;
  final List<ToolField> fields;

  factory WritingTool.fromJson(Map<String, dynamic> j) => WritingTool(
        id: str(j['id']),
        title: str(j['title']),
        description: str(j['description']),
        needsJob: strOrNull(j['needsJob']) ?? 'none',
        fields: objList(j['fields'])
            .map((f) => ToolField(
                  key: str(f['key']),
                  label: str(f['label']),
                  kind: strOrNull(f['kind']) ?? 'text',
                  required: boolOr(f['required'], false),
                  minLength: f['minLength'] is num ? (f['minLength'] as num).toInt() : null,
                  maxLength: f['maxLength'] is num ? (f['maxLength'] as num).toInt() : null,
                  choices: strList(f['choices']),
                ))
            .toList(),
      );
}

final writingToolsProvider = FutureProvider<List<WritingTool>>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/v1/ai/tools');
  return objList(obj(data)['items']).map(WritingTool.fromJson).toList();
});
