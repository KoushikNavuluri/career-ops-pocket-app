-- Career Ops: initial schema.
-- Every user-owned table carries user_id and is protected by row-level security that is
-- FORCED for the table owner, so a missed WHERE clause can't leak across accounts.

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE OR REPLACE FUNCTION app_current_user() RETURNS uuid
  LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.user_id', true), '')::uuid $$;

CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS trigger
  LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

-- Identity (resolved from the Entra token; not RLS-protected, only touched by the auth layer)
CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entra_oid     text NOT NULL UNIQUE,
  email         text,
  display_name  text,
  plan          text NOT NULL DEFAULT 'free' CHECK (plan IN ('free', 'pro')),
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE profiles (
  user_id           uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  alias             text CHECK (char_length(alias) <= 80),
  target_role       text CHECK (char_length(target_role) <= 120),
  north_star        text CHECK (char_length(north_star) <= 2000),
  target_market     text CHECK (target_market IN ('Europe', 'United States', 'India', 'Global')),
  work_model        text CHECK (work_model IN ('Remote', 'Hybrid', 'On-site')),
  target_base       numeric(14, 2) CHECK (target_base >= 0),
  currency          text CHECK (currency IN ('EUR', 'USD', 'GBP', 'INR')),
  include_keywords  text[] NOT NULL DEFAULT '{}',
  exclude_keywords  text[] NOT NULL DEFAULT '{}',
  work_auth_check   text NOT NULL DEFAULT 'Verify per role'
                    CHECK (work_auth_check IN ('Verify per role', 'No sponsorship stated', 'Sponsorship stated')),
  onboarded_at      timestamptz,
  version           integer NOT NULL DEFAULT 1,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE preferences (
  user_id               uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  theme                 text NOT NULL DEFAULT 'system' CHECK (theme IN ('system', 'light', 'evening')),
  resume_template       text NOT NULL DEFAULT 'editorial' CHECK (resume_template IN ('editorial', 'minimal', 'technical')),
  export_format         text NOT NULL DEFAULT 'pdf' CHECK (export_format IN ('pdf', 'markdown', 'latex')),
  posting_verification  boolean NOT NULL DEFAULT true,
  weekly_scan           boolean NOT NULL DEFAULT false,
  notifications         jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE jobs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  company       text NOT NULL CHECK (char_length(company) BETWEEN 1 AND 200),
  role          text NOT NULL CHECK (char_length(role) BETWEEN 1 AND 200),
  location      text CHECK (char_length(location) <= 200),
  work_model    text CHECK (work_model IN ('Remote', 'Hybrid', 'On-site')),
  salary_text   text CHECK (char_length(salary_text) <= 200),
  source        text NOT NULL DEFAULT 'pasted' CHECK (source IN ('pasted', 'greenhouse', 'lever', 'url')),
  source_url    text CHECK (char_length(source_url) <= 2000),
  external_id   text,
  description   text NOT NULL CHECK (char_length(description) BETWEEN 60 AND 60000),
  status        text NOT NULL DEFAULT 'Inbox'
                CHECK (status IN ('Inbox','Evaluated','Applied','Responded','Interview','Offer','Hired','Rejected','Discarded','SKIP')),
  saved         boolean NOT NULL DEFAULT false,
  score         numeric(2, 1) CHECK (score BETWEEN 1 AND 5),
  archetype     text,
  decision      text,
  legitimacy    text NOT NULL DEFAULT 'unverified',
  work_auth     text NOT NULL DEFAULT 'unknown',
  notes         text CHECK (char_length(notes) <= 10000),
  version       integer NOT NULL DEFAULT 1,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX jobs_external_uq ON jobs (user_id, source, external_id) WHERE external_id IS NOT NULL;
CREATE INDEX jobs_user_status_idx ON jobs (user_id, status, updated_at DESC);
CREATE INDEX jobs_user_score_idx ON jobs (user_id, score DESC NULLS LAST);
CREATE INDEX jobs_company_trgm ON jobs USING gin (company gin_trgm_ops);
CREATE INDEX jobs_role_trgm ON jobs USING gin (role gin_trgm_ops);

CREATE TABLE job_stage_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  job_id      uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  from_status text,
  to_status   text NOT NULL,
  note        text CHECK (char_length(note) <= 2000),
  feedback    text CHECK (char_length(feedback) <= 10000),
  actor       text NOT NULL CHECK (actor IN ('user', 'system')),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX job_stage_events_job_idx ON job_stage_events (job_id, created_at);

CREATE TABLE job_postings (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  job_id      uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  text        text NOT NULL,
  sha256      text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (job_id, sha256)
);

CREATE TABLE ai_runs (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  feature           text NOT NULL,
  model             text NOT NULL,
  prompt_version    text NOT NULL,
  input_tokens      integer NOT NULL DEFAULT 0,
  output_tokens     integer NOT NULL DEFAULT 0,
  cached_tokens     integer NOT NULL DEFAULT 0,
  reasoning_tokens  integer NOT NULL DEFAULT 0,
  credits           integer NOT NULL DEFAULT 0,
  latency_ms        integer NOT NULL DEFAULT 0,
  status            text NOT NULL CHECK (status IN ('ok', 'error')),
  error_code        text,
  reported_at       timestamptz,
  report_reason     text,
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ai_runs_user_idx ON ai_runs (user_id, created_at DESC);

CREATE TABLE evaluations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  job_id          uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  ai_run_id       uuid REFERENCES ai_runs(id) ON DELETE SET NULL,
  score           numeric(2, 1) NOT NULL CHECK (score BETWEEN 1 AND 5),
  archetype       text NOT NULL,
  decision        text NOT NULL,
  result          jsonb NOT NULL,
  prompt_version  text NOT NULL,
  model           text NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX evaluations_job_idx ON evaluations (job_id, created_at DESC);

CREATE TABLE cv_versions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind        text NOT NULL CHECK (kind IN ('master', 'tailored')),
  job_id      uuid REFERENCES jobs(id) ON DELETE SET NULL,
  markdown    text NOT NULL CHECK (char_length(markdown) <= 100000),
  source      text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'file', 'ai', 'import')),
  is_current  boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX cv_master_current_uq ON cv_versions (user_id) WHERE kind = 'master' AND is_current;
CREATE INDEX cv_versions_user_idx ON cv_versions (user_id, created_at DESC);

CREATE TABLE documents (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  job_id      uuid REFERENCES jobs(id) ON DELETE SET NULL,
  type        text NOT NULL CHECK (type IN ('report','application','resume','cover','email','draft','interview','digest','other')),
  title       text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 300),
  body_md     text NOT NULL CHECK (char_length(body_md) <= 200000),
  ai_run_id   uuid REFERENCES ai_runs(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX documents_user_idx ON documents (user_id, created_at DESC);

CREATE TABLE stories (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title       text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 200),
  competency  text NOT NULL CHECK (competency IN ('Ownership','Problem solving','Collaboration','Leadership','Learning')),
  situation   text NOT NULL CHECK (char_length(situation) <= 4000),
  task        text NOT NULL CHECK (char_length(task) <= 4000),
  action      text NOT NULL CHECK (char_length(action) <= 4000),
  result      text NOT NULL CHECK (char_length(result) <= 4000),
  reflection  text NOT NULL CHECK (char_length(reflection) <= 4000),
  version     integer NOT NULL DEFAULT 1,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE assistant_threads (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title           text NOT NULL DEFAULT 'New conversation',
  context_job_id  uuid REFERENCES jobs(id) ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX assistant_threads_user_idx ON assistant_threads (user_id, updated_at DESC);

CREATE TABLE assistant_messages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  thread_id   uuid NOT NULL REFERENCES assistant_threads(id) ON DELETE CASCADE,
  role        text NOT NULL CHECK (role IN ('user', 'assistant')),
  content     text NOT NULL CHECK (char_length(content) <= 40000),
  ai_run_id   uuid REFERENCES ai_runs(id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX assistant_messages_thread_idx ON assistant_messages (thread_id, created_at);

CREATE TABLE consents (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  feature         text NOT NULL,
  policy_version  text NOT NULL,
  granted_at      timestamptz NOT NULL DEFAULT now(),
  revoked_at      timestamptz
);
CREATE UNIQUE INDEX consents_active_uq ON consents (user_id, feature, policy_version) WHERE revoked_at IS NULL;

CREATE TABLE usage_counters (
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  period        text NOT NULL CHECK (period ~ '^[0-9]{4}-[0-9]{2}$'),
  credits_used  integer NOT NULL DEFAULT 0 CHECK (credits_used >= 0),
  PRIMARY KEY (user_id, period)
);

-- Retrieval index (filled by the embedding worker in a later phase).
CREATE TABLE content_chunks (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source_type  text NOT NULL,
  source_id    uuid NOT NULL,
  span         text,
  text         text NOT NULL,
  embedding    vector(1536),
  tsv          tsvector GENERATED ALWAYS AS (to_tsvector('english', text)) STORED,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX content_chunks_user_idx ON content_chunks (user_id, source_type, source_id);
CREATE INDEX content_chunks_tsv_idx ON content_chunks USING gin (tsv);
CREATE INDEX content_chunks_embedding_idx ON content_chunks USING hnsw (embedding vector_cosine_ops);

-- Security audit trail. No FK so records survive account deletion; stores a hash, not the id.
CREATE TABLE audit_events (
  id          bigserial PRIMARY KEY,
  actor_hash  text NOT NULL,
  action      text NOT NULL,
  detail      jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- updated_at triggers
CREATE TRIGGER users_touch BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER profiles_touch BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER preferences_touch BEFORE UPDATE ON preferences FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER jobs_touch BEFORE UPDATE ON jobs FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER documents_touch BEFORE UPDATE ON documents FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER stories_touch BEFORE UPDATE ON stories FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER assistant_threads_touch BEFORE UPDATE ON assistant_threads FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- Row-level security on every user-owned table.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'profiles','preferences','jobs','job_stage_events','job_postings','ai_runs','evaluations',
    'cv_versions','documents','stories','assistant_threads','assistant_messages','consents',
    'usage_counters','content_chunks'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY %I ON %I USING (user_id = app_current_user()) WITH CHECK (user_id = app_current_user())',
      t || '_owner', t
    );
  END LOOP;
END $$;
