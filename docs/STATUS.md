# Build status (28 Oct 2026)

**Built**
- API: Fastify 5 + PostgreSQL/pgvector with forced row-level security; Entra External ID token
  validation; GPT-5 mini gateway (consent, monthly credits, strict JSON output, one repair retry,
  metering); jobs and pipeline transitions; A-H evaluations; CV versions; stories; documents;
  10 writing tools; streaming assistant (SSE); data export and account deletion. 34 unit tests,
  plus integration tests against real Postgres in CI.
- Mobile: Flutter (Riverpod 3, go_router, flutter_appauth PKCE). Splash, sign-in, onboarding,
  Today, Explore, Pipeline, role detail with evaluation, resume workspace, Studio and writing
  tools, assistant, story bank, documents, You (direction, theme, AI usage, consents, export, delete).
- Infra: `infra/main.bicep` and the `deploy` workflow; CI with reports on the `ci-reports` branch;
  a workflow that generates the Android/iOS folders.

**Pending**
- First CI pass (the Flutter code had not been compiled before this push).
- Azure values from the owner (docs/SETUP-AZURE.md).
- CV file upload/parsing, embeddings retrieval, notifications, offline cache, store assets.
