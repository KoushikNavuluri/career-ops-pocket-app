# GitHub Actions workflows (one-time step to enable)

These three files belong in `.github/workflows/`. The automation that created this repository is not
allowed to write workflow files (GitHub requires the `workflow` permission for that), so they are parked
here. Moving them takes one minute and only has to be done once.

| File | What it does |
| --- | --- |
| `ci.yml` | On every push to `main`: API install, typecheck, unit + integration tests (real Postgres with pgvector), build; Flutter `pub get`, `analyze`, `test`; Bicep compile. Publishes a readable summary to the `ci-reports` branch (`latest.md`). |
| `scaffold-mobile-platforms.yml` | Runs once: `flutter create` for Android and iOS, then `apps/mobile/tool/configure_platforms.py` (sign-in redirect scheme, internet permission, min OS versions, "Career Ops" display name), and commits the result. |
| `deploy.yml` | Provisions Azure with `infra/main.bicep` and ships the API container. Does nothing until the repository variable `AZURE_DEPLOY_ENABLED` is `true` (see `docs/SETUP-AZURE.md`). |

## Option A: on your computer

```bash
git clone https://github.com/KoushikNavuluri/career-ops-pocket-app.git
cd career-ops-pocket-app
mkdir -p .github
git mv ops/workflows .github/workflows
git commit -m "ci: enable GitHub Actions workflows"
git push
```

## Option B: in the browser

For each of the three `.yml` files: open it on GitHub, click the pencil (Edit), change the file name box
from `ops/workflows/ci.yml` to `.github/workflows/ci.yml` (typing `/` creates folders), and commit.

## Also check once

Repository Settings, then Actions, then General: "Workflow permissions" must be **Read and write**
(the CI report and the platform scaffold commit back to the repository).
