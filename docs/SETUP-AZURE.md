# Azure setup for Career Ops

You create five things by hand (about 60-90 minutes the first time). The `deploy` GitHub
workflow creates everything else with Bicep (`infra/main.bicep`).

| # | You create (by hand) | Where |
|---|---|---|
| 1 | Azure subscription, resource group, providers, budget | portal.azure.com |
| 2 | Entra External ID tenant, 2 app registrations, sign-up/sign-in user flow | entra.microsoft.com |
| 3 | GitHub deploy identity (OIDC, no secrets) with rights on the resource group | entra.microsoft.com + portal |
| 4 | GPT-5 mini quota check | ai.azure.com |
| 5 | GitHub secrets and variables | GitHub repo settings |

The pipeline then creates: PostgreSQL Flexible Server (B1ms, pgvector), Azure OpenAI with a
`gpt-5-mini` Global Standard deployment, Container Apps environment + API, Container Registry,
Key Vault, Storage, Log Analytics, Application Insights, a managed identity and its role assignments.

> Never paste passwords or client secrets into chat or commits. Put them straight into GitHub secrets.
> IDs (tenant, client, subscription) are not secrets and are fine to share.

---

## 1. Subscription, resource group, providers, budget

1. Sign in at https://portal.azure.com. If you have no subscription: **Subscriptions → + Add →
   Pay-As-You-Go** (free trials have tight AI quota; Pay-As-You-Go is recommended).
2. **Subscriptions → your subscription → Overview**: copy the **Subscription ID**.
3. **Subscription → Settings → Resource providers**. Select and **Register** each of:
   `Microsoft.App`, `Microsoft.ContainerRegistry`, `Microsoft.DBforPostgreSQL`,
   `Microsoft.CognitiveServices`, `Microsoft.KeyVault`, `Microsoft.OperationalInsights`,
   `Microsoft.Insights`, `Microsoft.Storage`, `Microsoft.ManagedIdentity`,
   `Microsoft.AzureActiveDirectory`. Wait until each shows *Registered*.
4. **Resource groups → + Create**: name `rg-careerops-dev`, region **Central India** → Review + create.
5. **Cost Management → Budgets → + Add**: scope = the subscription, monthly amount e.g. USD 50,
   alerts at 50 %, 80 %, 100 % to your email. (Expected dev cost is roughly USD 25-45/month.)

## 2. Entra External ID (customer sign-in, email + password)

### 2a. Create the external tenant
1. https://entra.microsoft.com → **Entra ID → Overview → Manage tenants → + Create**.
2. Choose **External** → Continue.
3. Tenant name `Career Ops`, domain name e.g. `careerops` (this becomes your **tenant subdomain**,
   so sign-in pages live at `careerops.ciamlogin.com`). Country/region: India.
4. Link it to your subscription and `rg-careerops-dev` (billing; first 50,000 monthly users are free).
5. Create. It can take up to 30 minutes.
6. Switch into the new tenant (gear icon → **Directories + subscriptions** → Switch).
7. **Entra ID → Overview**: copy the **Tenant ID**. The **Primary domain** is
   `careerops.onmicrosoft.com`; the part before `.onmicrosoft.com` is the **tenant subdomain**.

### 2b. Register the API ("Career Ops API")
1. **App registrations → + New registration**. Name `Career Ops API`. Supported account types:
   *Accounts in this organizational directory only*. No redirect URI. **Register**.
2. Copy the **Application (client) ID** → this is `AUTH_API_CLIENT_ID`.
3. **Expose an API → Add** next to *Application ID URI* → accept `api://<client-id>` → Save.
4. **+ Add a scope**: name `access_as_user`, *Admins only* (or *Admins and users*),
   display name `Access Career Ops`, description `Lets the app call the Career Ops API for you`,
   State Enabled → **Add scope**.
5. **Manifest**: make sure `"requestedAccessTokenVersion": 2` (inside `"api"`) → Save.
6. **Token configuration → + Add optional claim → Access → email** → Add (accept the Graph
   permission prompt if shown).

### 2c. Register the mobile app ("Career Ops Mobile")
1. **App registrations → + New registration**. Name `Career Ops Mobile`, single tenant.
   Redirect URI: platform **Public client/native (mobile & desktop)**, value
   `com.koushiknavuluri.careerpocket://auth` → **Register**.
2. Copy the **Application (client) ID** → this is `AUTH_MOBILE_CLIENT_ID`.
3. **API permissions → + Add a permission → APIs my organization uses → Career Ops API →
   Delegated → access_as_user** → Add.
4. Also make sure Microsoft Graph delegated `openid`, `offline_access`, `profile` are listed
   (add them under **Microsoft Graph → Delegated** if not).
5. **Grant admin consent for Career Ops** → Yes. All rows should show a green check.

### 2d. Email + password user flow
1. **External Identities → User flows → + New user flow**. Name `signup_signin`.
2. Identity providers: **Email with password**. Attributes: **Display Name**. **Create**.
3. Open the flow → **Applications → + Add application → Career Ops Mobile** → Select.
4. Password reset: **Authentication methods → Email OTP** → enable for all users; then
   **Company branding → Default sign-in → Sign-in form** → tick *Show self-service password reset*.
5. Optional branding (same page): background `#F7F7F2`, logo, banner text `Career Ops`.
6. Test: **User flows → signup_signin → Run user flow** with app *Career Ops Mobile*, create an
   account with your email. Seeing the "redirect" error page at the end is expected.
7. Check the discovery URL opens in a browser:
   `https://<subdomain>.ciamlogin.com/<tenant-id>/v2.0/.well-known/openid-configuration`

### 2e. (Before store launch) Account-deletion app
Needed so "Delete account" also removes the sign-in identity. Can wait until later.
1. **App registrations → + New registration** `Career Ops Account Cleanup`, single tenant.
2. **API permissions → Microsoft Graph → Application permissions → User.ReadWrite.All** → Add →
   **Grant admin consent**.
3. **Certificates & secrets → + New client secret** (24 months). Copy the **Value** straight into
   the GitHub secret `GRAPH_CLIENT_SECRET`. Copy the client ID into variable `GRAPH_CLIENT_ID`.

## 3. GitHub deploy identity (in your main Azure tenant, not the external one)
1. Switch back to your default directory (gear → Directories + subscriptions).
2. **Entra ID → App registrations → + New registration** `github-careerops-deploy`, single tenant → Register.
   Copy its **Application (client) ID** (`AZURE_CLIENT_ID`) and **Directory (tenant) ID** (`AZURE_TENANT_ID`).
3. **Certificates & secrets → Federated credentials → + Add credential**. Scenario
   *GitHub Actions deploying Azure resources*. Organization `KoushikNavuluri`, Repository
   `career-ops-pocket-app`, Entity type **Branch**, Branch `main`, Name `main` → Add.
4. Portal → **Resource groups → rg-careerops-dev → Access control (IAM) → + Add → Add role assignment**:
   - Role **Contributor** → Members: *User, group, or service principal* → select
     `github-careerops-deploy` → Review + assign.
   - Again: role **Role Based Access Control Administrator** (Privileged roles tab) → same member →
     on *Conditions* choose *Allow user to only assign selected roles* → select **AcrPull**,
     **Key Vault Secrets User**, **Storage Blob Data Contributor**, **Cognitive Services OpenAI User** → assign.
     (Simpler but broader alternative: give it **Owner** on this resource group only.)

## 4. GPT-5 mini quota
1. https://ai.azure.com → **Management center → Quota** (or *Models + endpoints → Quota*).
2. Filter: model `gpt-5-mini`, deployment type **Global Standard**, region **East US 2**.
3. You need at least **50K TPM** free. If it shows 0, click **Request quota** and ask for 100K TPM.
   gpt-5-mini does not need a registration form (only full gpt-5 does).
4. Nothing else to create here: the pipeline creates the Azure OpenAI resource in East US 2 and a
   deployment named `gpt-5-mini` (version 2025-08-07). Global Standard may process requests in any
   Azure region; use a Data Zone deployment later if you need US/EU residency.

## 5. GitHub settings
Repo → **Settings → Secrets and variables → Actions**.

**Secrets**
| Name | Value |
|---|---|
| `AZURE_CLIENT_ID` | client ID of `github-careerops-deploy` |
| `AZURE_TENANT_ID` | your main tenant ID |
| `AZURE_SUBSCRIPTION_ID` | subscription ID |
| `POSTGRES_ADMIN_PASSWORD` | 20+ random characters, e.g. from `openssl rand -base64 24` |
| `GRAPH_CLIENT_SECRET` | optional, from 2e |

**Variables**
| Name | Value |
|---|---|
| `AZURE_RESOURCE_GROUP` | `rg-careerops-dev` |
| `AZURE_OPENAI_LOCATION` | `eastus2` |
| `AUTH_TENANT_ID` | external tenant ID (2a.7) |
| `AUTH_TENANT_SUBDOMAIN` | e.g. `careerops` |
| `AUTH_API_CLIENT_ID` | from 2b.2 |
| `AUTH_MOBILE_CLIENT_ID` | from 2c.2 |
| `GRAPH_CLIENT_ID` | optional, from 2e |
| `AZURE_DEPLOY_ENABLED` | `true` (set this last) |

Then **Actions → deploy → Run workflow**. It provisions Azure, builds the API image, deploys it,
runs database migrations and waits for `/readyz`. The API URL is written to the `ci-reports`
branch (`deploy.md`).

## 6. Mobile app configuration
Copy `apps/mobile/env/dev.example.json` to `env/dev.json` and fill in:
`API_BASE_URL` (deploy output), `AUTH_DISCOVERY_URL` (2d.7), `AUTH_CLIENT_ID` (2c.2),
`AUTH_API_SCOPE` = `api://<AUTH_API_CLIENT_ID>/access_as_user`. Run with
`flutter run --dart-define-from-file=env/dev.json`.

## What to send back
Non-secret values only: subscription ID, main tenant ID, external tenant ID, tenant subdomain,
API client ID, mobile client ID, and a note once the GitHub secrets and variables are saved.
