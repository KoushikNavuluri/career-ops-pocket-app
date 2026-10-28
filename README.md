# Career Ops

Human-in-the-loop career workspace: Flutter app for Android and iOS on an Azure backend.

| Path | What |
|---|---|
| `apps/mobile` | Flutter app. Email + password sign-in through Microsoft Entra External ID. |
| `services/api` | TypeScript API (Fastify) for Azure Container Apps, PostgreSQL + pgvector, Azure OpenAI GPT-5 mini. |
| `infra` | Bicep for every Azure resource. |
| `docs` | Setup guide, decisions, status. |

- Set up Azure: [docs/SETUP-AZURE.md](docs/SETUP-AZURE.md)
- What is built: [docs/STATUS.md](docs/STATUS.md)
- API locally: `cd services/api && cp .env.example .env && npm install && npm run migrate && npm run dev`
- App locally: `cd apps/mobile && cp env/dev.example.json env/dev.json && flutter run --dart-define-from-file=env/dev.json`
- CI results are published to the `ci-reports` branch (`latest.md`).

Evaluation methodology adapted from [career-ops](https://github.com/career-ops-hq/career-ops) (MIT). See NOTICE.
