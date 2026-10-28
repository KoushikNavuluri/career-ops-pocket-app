import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/api/api_client.dart';
import '../../core/util/json.dart';
import 'models.dart';

final jobsProvider = FutureProvider<List<JobSummary>>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/v1/jobs', query: {'limit': 500});
  return objList(obj(data)['items']).map(JobSummary.fromJson).toList();
});

final jobDetailProvider = FutureProvider.family<JobDetail, String>((ref, id) async {
  final data = await ref.watch(apiClientProvider).get('/v1/jobs/$id');
  return JobDetail.fromJson(obj(data));
});

final todayProvider = FutureProvider<TodayView>((ref) async {
  final data = await ref.watch(apiClientProvider).get('/v1/today');
  return TodayView.fromJson(obj(data));
});

final jobsActionsProvider = Provider<JobsActions>((ref) => JobsActions(ref));

class DuplicateJob implements Exception {
  DuplicateJob(this.existingId);
  final String existingId;
}

class JobsActions {
  JobsActions(this._ref);
  final Ref _ref;

  ApiClient get _api => _ref.read(apiClientProvider);

  void _refreshLists([String? id]) {
    _ref.invalidate(jobsProvider);
    _ref.invalidate(todayProvider);
    if (id != null) _ref.invalidate(jobDetailProvider(id));
  }

  Future<String> create({
    required String company,
    required String role,
    required String description,
    String? location,
    String? workModel,
    String? salaryText,
  }) async {
    try {
      final data = await _api.post('/v1/jobs', {
        'company': company,
        'role': role,
        'description': description,
        if (location != null && location.isNotEmpty) 'location': location,
        if (workModel != null) 'work_model': workModel,
        if (salaryText != null && salaryText.isNotEmpty) 'salary_text': salaryText,
      });
      _refreshLists();
      return str(obj(data)['id']);
    } on ApiException catch (e) {
      if (e.code == 'duplicate_job' && e.extra['existingId'] is String) throw DuplicateJob(e.extra['existingId'] as String);
      rethrow;
    }
  }

  Future<void> setSaved(String id, bool saved) async {
    await _api.patch('/v1/jobs/$id', {'saved': saved});
    _refreshLists(id);
  }

  Future<void> transition(String id, String to, {String? note, String? feedback}) async {
    await _api.post('/v1/jobs/$id/transitions', {
      'to': to,
      if (note != null && note.isNotEmpty) 'note': note,
      if (feedback != null && feedback.isNotEmpty) 'feedback': feedback,
    });
    _refreshLists(id);
  }

  /// Runs the GPT-5 mini evaluation. Throws [ApiException] with code `consent_required`
  /// when the user hasn't agreed yet.
  Future<void> evaluate(String id, {bool consent = false}) async {
    await _api.post('/v1/jobs/$id/evaluations', {if (consent) 'consent': true});
    _refreshLists(id);
    _ref.invalidate(meProvider);
  }

  Future<void> delete(String id) async {
    await _api.delete('/v1/jobs/$id');
    _refreshLists();
  }

  Future<String> exportCsv() => _api.getText('/v1/jobs/export.csv');

  Future<void> reportAiOutput(String aiRunId, String reason) async {
    await _api.post('/v1/ai/runs/$aiRunId/report', {'reason': reason});
  }
}
