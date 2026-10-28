import '../../core/util/json.dart';

const kStatuses = ['Inbox', 'Evaluated', 'Applied', 'Responded', 'Interview', 'Offer', 'Hired', 'Rejected', 'Discarded', 'SKIP'];
const kWorkModels = ['Remote', 'Hybrid', 'On-site'];

class JobSummary {
  const JobSummary({
    required this.id,
    required this.company,
    required this.role,
    required this.status,
    required this.saved,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.location,
    this.workModel,
    this.salaryText,
    this.score,
    this.archetype,
    this.decision,
    this.legitimacy,
    this.workAuth,
  });

  final String id;
  final String company;
  final String role;
  final String status;
  final bool saved;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? location;
  final String? workModel;
  final String? salaryText;
  final double? score;
  final String? archetype;
  final String? decision;
  final String? legitimacy;
  final String? workAuth;

  factory JobSummary.fromJson(Map<String, dynamic> j) => JobSummary(
        id: str(j['id']),
        company: str(j['company']),
        role: str(j['role']),
        status: strOrNull(j['status']) ?? 'Inbox',
        saved: boolOr(j['saved'], false),
        version: intOr(j['version'], 1),
        createdAt: dateOrNull(j['created_at']) ?? DateTime.now(),
        updatedAt: dateOrNull(j['updated_at']) ?? DateTime.now(),
        location: strOrNull(j['location']),
        workModel: strOrNull(j['work_model']),
        salaryText: strOrNull(j['salary_text']),
        score: numOrNull(j['score']),
        archetype: strOrNull(j['archetype']),
        decision: strOrNull(j['decision']),
        legitimacy: strOrNull(j['legitimacy']),
        workAuth: strOrNull(j['work_auth']),
      );

  String get meta => [location, workModel].whereType<String>().join(' · ');
}

class Job extends JobSummary {
  const Job({
    required super.id,
    required super.company,
    required super.role,
    required super.status,
    required super.saved,
    required super.version,
    required super.createdAt,
    required super.updatedAt,
    required this.description,
    super.location,
    super.workModel,
    super.salaryText,
    super.score,
    super.archetype,
    super.decision,
    super.legitimacy,
    super.workAuth,
    this.notes,
    this.sourceUrl,
  });

  final String description;
  final String? notes;
  final String? sourceUrl;

  factory Job.fromJson(Map<String, dynamic> j) {
    final s = JobSummary.fromJson(j);
    return Job(
      id: s.id,
      company: s.company,
      role: s.role,
      status: s.status,
      saved: s.saved,
      version: s.version,
      createdAt: s.createdAt,
      updatedAt: s.updatedAt,
      location: s.location,
      workModel: s.workModel,
      salaryText: s.salaryText,
      score: s.score,
      archetype: s.archetype,
      decision: s.decision,
      legitimacy: s.legitimacy,
      workAuth: s.workAuth,
      description: str(j['description']),
      notes: strOrNull(j['notes']),
      sourceUrl: strOrNull(j['source_url']),
    );
  }
}

class StageEvent {
  const StageEvent({required this.to, required this.actor, required this.at, this.from, this.note, this.feedback});
  final String? from;
  final String to;
  final String actor;
  final DateTime at;
  final String? note;
  final String? feedback;

  factory StageEvent.fromJson(Map<String, dynamic> j) => StageEvent(
        from: strOrNull(j['from_status']),
        to: str(j['to_status']),
        actor: strOrNull(j['actor']) ?? 'user',
        at: dateOrNull(j['created_at']) ?? DateTime.now(),
        note: strOrNull(j['note']),
        feedback: strOrNull(j['feedback']),
      );
}

class Requirement {
  const Requirement(this.raw);
  final Map<String, dynamic> raw;
  String get requirement => str(raw['requirement']);
  String get importance => str(raw['importance']);
  String get evidenceTier => str(raw['evidence_tier']);
  String get jdSignal => str(raw['jd_signal']);
  String get match => str(raw['match']);
  String get evidenceOrGap => str(raw['evidence_or_gap']);
  String get mitigation => str(raw['mitigation']);
}

/// Structured A-H evaluation report (see services/api/src/domain/evaluation.ts).
class EvaluationReport {
  EvaluationReport(this.raw);
  final Map<String, dynamic> raw;

  Map<String, dynamic> get _blocks => obj(raw['blocks']);
  Map<String, dynamic> block(String key) => obj(_blocks[key]);

  String get verdict => str(raw['verdict']);
  String get decision => str(raw['decision']);
  String get confidence => str(raw['confidence']);
  String get archetype => str(raw['archetype']);
  double? get score => numOrNull(raw['score']);
  Map<String, String> get scoreEvidence => obj(raw['score_evidence']).map((k, v) => MapEntry(k, str(v)));
  List<String> get topStrengths => strList(raw['top_strengths']);
  List<String> get hardStops => strList(raw['hard_stops']);
  List<String> get softGaps => strList(raw['soft_gaps']);
  List<String> get keywords => strList(raw['keywords']);
  List<String> get confidenceGaps => strList(raw['confidence_gaps']);
  String get nextAction => str(raw['next_action']);

  Map<String, dynamic> get roleSummary => block('a_role_summary');
  List<Requirement> get requirements => objList(block('b_cv_match')['requirements']).map(Requirement.new).toList();
  String get gapsStrategy => str(block('b_cv_match')['gaps_strategy']);
  Map<String, dynamic> get level => block('c_level_strategy');
  Map<String, dynamic> get comp => block('d_comp_demand');
  List<Map<String, dynamic>> get customization => objList(_blocks['e_customization']);
  Map<String, dynamic> get interview => block('f_interview_plan');
  Map<String, dynamic> get legitimacy => block('g_legitimacy');
  List<Map<String, dynamic>> get answers => objList(_blocks['h_application_answers']);
}

class Evaluation {
  const Evaluation({required this.id, required this.score, required this.decision, required this.report, required this.model, required this.createdAt, this.aiRunId});
  final String id;
  final double score;
  final String decision;
  final EvaluationReport report;
  final String model;
  final DateTime createdAt;
  final String? aiRunId;

  factory Evaluation.fromJson(Map<String, dynamic> j) => Evaluation(
        id: str(j['id']),
        score: numOrNull(j['score']) ?? 0,
        decision: str(j['decision']),
        report: EvaluationReport(obj(j['result'])),
        model: str(j['model']),
        createdAt: dateOrNull(j['created_at']) ?? DateTime.now(),
        aiRunId: strOrNull(j['ai_run_id']),
      );
}

class JobDetail {
  const JobDetail({required this.job, required this.events, required this.allowedTransitions, this.evaluation});
  final Job job;
  final Evaluation? evaluation;
  final List<StageEvent> events;
  final List<String> allowedTransitions;

  bool get canEvaluate => job.status == 'Inbox' || job.status == 'Evaluated';

  factory JobDetail.fromJson(Map<String, dynamic> j) {
    final e = j['evaluation'];
    return JobDetail(
      job: Job.fromJson(obj(j['job'])),
      evaluation: e is Map ? Evaluation.fromJson(obj(e)) : null,
      events: objList(j['events']).map(StageEvent.fromJson).toList(),
      allowedTransitions: strList(j['allowedTransitions']),
    );
  }
}

class NextMove {
  const NextMove({required this.kind, required this.title, required this.detail, this.jobId});
  final String kind;
  final String title;
  final String detail;
  final String? jobId;
}

class TodayView {
  const TodayView({required this.counts, required this.strongMatches, required this.nextMoves});
  final Map<String, int> counts;
  final List<JobSummary> strongMatches;
  final List<NextMove> nextMoves;

  factory TodayView.fromJson(Map<String, dynamic> j) => TodayView(
        counts: obj(j['counts']).map((k, v) => MapEntry(k, intOr(v, 0))),
        strongMatches: objList(j['strongMatches'])
            .map((m) => JobSummary.fromJson({...m, 'saved': false, 'version': 1}))
            .toList(),
        nextMoves: objList(j['nextMoves'])
            .map((m) => NextMove(kind: str(m['kind']), title: str(m['title']), detail: str(m['detail']), jobId: strOrNull(m['jobId'])))
            .toList(),
      );
}

/// Client-side filtering over the cached list (the API supports the same filters).
List<JobSummary> filterJobs(
  List<JobSummary> all, {
  String query = '',
  String? status,
  bool savedOnly = false,
  double? minScore,
  String? workModel,
  String sort = 'recent',
}) {
  final q = query.trim().toLowerCase();
  final out = all.where((j) {
    if (status != null && j.status != status) return false;
    if (savedOnly && !j.saved) return false;
    if (minScore != null && (j.score ?? 0) < minScore) return false;
    if (workModel != null && j.workModel != workModel) return false;
    if (q.isNotEmpty && !j.company.toLowerCase().contains(q) && !j.role.toLowerCase().contains(q)) return false;
    return true;
  }).toList();
  switch (sort) {
    case 'score':
      out.sort((a, b) => (b.score ?? -1).compareTo(a.score ?? -1));
    case 'company':
      out.sort((a, b) => a.company.toLowerCase().compareTo(b.company.toLowerCase()));
    default:
      out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
  return out;
}
