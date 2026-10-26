# Knowledge Hub — Deployment Summary Report

**Date:** 26 October 2026
**Target environment:** Windows Server hosts (e.g. `10.10.6.116`), code pre-deployed at `D:\<project>-code\AI-Python`
**Delivered via:** Ansible provisioning (`ansible/windows/windows.yml`) + Jenkins pipeline (`Jenkinsfile-build-knowledgehub-windows`)
**Status:** All code changes merged to `main` (PRs #1–#35). Final on-target confirmation steps are listed in §6.

---

## 1. What was newly added

### 1.1 New Ansible roles (additive — existing legacy roles untouched)

| Role | What it installs | Key details |
|---|---|---|
| `postgres14` (name kept from the original plan) | **PostgreSQL 18.6-5** | New instance on **port 5433**; apps in `D:\QASIP\Apps\postgres18`, data in `D:\QASIP\Data\postgres18`, service `postgresql-x64-18`. Coexists with the legacy PostgreSQL 10 on 5432, which is untouched. |
| `postgres14` (continued) | **pgvector 0.8.7** | Built from source on Windows (`nmake /F Makefile.win` with Visual C++ Build Tools — pgvector ships no Windows binaries). Required by the Hub schema. |
| `postgres14` (continued) | **pgAdmin 4 9.18** | Database administration UI for both PG instances. |
| `node18` | **Node.js 18.20.8** | Side-by-side in `D:\QASIP\Apps\node18`, deliberately **not** on PATH — legacy Node 10 stays the system default. |
| `python312` | **Python 3.12.10** | Side-by-side in `C:\Program Files\Python312` (`PrependPath=0`) — system Python 3.11 untouched. |
| `qdrant` | **Qdrant 1.19.2** | NSSM service `QASIP-Qdrant`, ports 6333/6334, storage `D:\QASIP\Data\qdrant\storage`, Windows Firewall rule `qdrant-tcp-6333`. |

### 1.2 Database objects created for the Hub

- Databases: `atms_master` and **`qasip_hub`**
- Login role: **`kh_app`** (LOGIN, **SUPERUSER** — see issue #7 in §5), `GRANT ALL` on `qasip_hub`, `USAGE, CREATE` on schema `public`
- `vector` extension enabled (pgvector)

### 1.3 New Jenkins pipeline — `Jenkinsfile-build-knowledgehub-windows`

A complete build/deploy pipeline for the Hub (15 stages: Validate → Resolve Host Entries → Verify Source Code → Stop Service → Create Virtual Environment → Setup Backend → Install Adapters → Generate Secret Key → Verify Adapters → Apply Database Migrations → Configure Backend Service (NSSM) → Start Backend & Verify Health → Build Frontend → Publish Frontend to Nginx → Verify Deployment). Policy decisions baked in:

- **No Git checkout/pull** — the code already on the machine is deployed as-is.
- Only two job parameters: `PROJECT_TARGET_MACHINE` and `NOTIFICATION_EMAILS`.
- Hostname derived at runtime (`<project>.qajarvis.com`) from the hosts entries written by the infra pipeline.
- The Fernet secret key (`Knowledge_Hub\.qasip_hub_secret_key`) is generated **once**, reused on every redeploy, and never printed to logs.

---

## 2. What was configured

### 2.1 Runtime layout (ports & services)

| Component | Port | How it runs |
|---|---|---|
| Knowledge_Hub **backend** | **8037** | NSSM service `QASIP-KnowledgeHub` — `uvicorn qasip_hub.main:app --host 0.0.0.0 --port 8037 --workers 2` |
| Knowledge_Hub_Admin **frontend** | **8000** | Static files served by Nginx (no separate frontend process) |
| PostgreSQL 18 (Hub) | 5433 | Windows service `postgresql-x64-18` |
| Qdrant | 6333 | NSSM service `QASIP-Qdrant` |
| Legacy ATMS UI (Nginx) | 6003 | Untouched |
| Legacy PostgreSQL 10 | 5432 | Untouched |

Internal services (PostgreSQL, Qdrant) are reached via **localhost only** — PostgreSQL's default `pg_hba.conf` rejects LAN-IP/hostname connections. Both 8037 and 8000 answer on `localhost` and on `<hostname>`; the setup is plain HTTP (no TLS, no :80/:443 listener by design).

### 2.2 Nginx configuration (Ansible `roles/nginx`, merged to `nginx.conf`)

An unconditional server block added alongside the existing ATMS block:

```nginx
server {
    listen       8000;
    server_name  localhost _;
    root   html/knowledge-hub;              # pipeline publishes the built UI here
    location /        { try_files $uri $uri/ /index.html; }          # SPA fallback
    location = /health { proxy_pass http://127.0.0.1:8037; }         # → backend
    location /mcp/     { proxy_pass http://127.0.0.1:8037;           # → backend (SSE:
                         proxy_buffering off; proxy_read_timeout 86400s; }
}
```

The role also: validates the rendered config, clears leftover `nginx.exe` processes before restarting, asserts `listen 8000;` exists in the **deployed** config, waits for the :8000 listener (dumping `error.log` if it doesn't bind), and records the separate backend/frontend directories (`D:\<project>-code\AI-Python\Knowledge_Hub[_Admin]`) explicitly.

### 2.3 Service environment (set by the pipeline via NSSM)

- `QASIP_HUB_DATABASE_URL = postgresql://kh_app:***@localhost:5433/qasip_hub` (credentials from Jenkins `knowledgehub-db-credentials`, bound only where needed)
- `QASIP_HUB_SECRET_KEY` — generated Fernet key (above)
- `QASIP_HUB_PORT=8037`, CORS / public URL for the :8000 UI origins
- Qdrant `http://localhost:6333`, collection `ku_index`, local embeddings (`BAAI/bge-small-en-v1.5`), LLM provider `openai` (API keys from optional Jenkins credentials — missing keys warn, they don't block deployment)

### 2.4 Credentials model

| Credential (Jenkins) | Type | Purpose |
|---|---|---|
| `knowledgehub-db-credentials` | Username+password | `kh_app` DB login (mandatory) |
| `knowledgehub-openai-api-key` | Secret text | LLM calls (optional — deploy proceeds without it) |
| `knowledgehub-qdrant-api-key` | Secret text | Qdrant auth (optional while Qdrant runs without auth) |

Note: Ansible deliberately does **not** manage the `kh_app` password (`pg14_hub_db_password: ""`) — the Jenkins credential is the source of truth and must match the database.

---

## 3. Verification built into the deployment

- **Provisioning** asserts the deployed `nginx.conf` contains the :8000 listener, UI root and :8037 proxies, and that `http://localhost:8000/` answers.
- **Pipeline** verifies the NSSM-stored environment (it prints only the `DATABASE_URL` host part — `@localhost:5433/qasip_hub` — never the password), runs Alembic migrations (0001 → 0021 confirmed), and health-checks:
  - **Fatal:** `curl http://localhost:8037/health` and `curl http://localhost:8037/mcp/tools`
  - **Warning-only:** `http://localhost:8000/`, `http://<hostname>:8000/`, `http://<hostname>:8000/health`, `/mcp/tools`

---

## 4. Issues faced and how they were resolved

| # | Issue | Root cause | Resolution |
|---|---|---|---|
| 1 | PostgreSQL 14 approaching EOL (12 Nov 2026) | Original pin was PG 14.24 | Upgraded the `postgres14` role in place to **PostgreSQL 18.6-5** (role/variable names kept) |
| 2 | pgvector has no Windows binary | Source-only distribution | Built **pgvector 0.8.7** with VS C++ Build Tools via `nmake /F Makefile.win` |
| 3 | Alembic failed: `no pg_hba.conf entry` | DB accessed via hostname/LAN IP; PG only allows loopback | Standardised on **localhost:5433** everywhere (single source) |
| 4 | `permission denied for schema public`; migration 0017 failed (`DROP EXTENSION vector must be owner`) | `kh_app` lacked rights; pgvector isn't a "trusted" extension | Made `kh_app` **SUPERUSER** in Ansible (`pg14_hub_db_superuser: true`) — verified manually first; migrations 0001→0021 then pass |
| 5 | `pip install -e .` failed: package requires Python ≥ 3.12 | venv inherited system Python 3.11 | pipeline recreates the venv with Python 3.12 explicitly unless it already is 3.12 |
| 6 | pip self-upgrade failed on Windows | `pip.exe` can't replace itself while running | Use `python -m pip` for the upgrade |
| 7 | Adapters "not found" (`qasip-hub>=0.1.0 (from versions: none)`) | Adapters installed before the Hub itself | Reordered stages: Hub first, adapters after, entry-points verified |
| 8 | Migrations aborted before running when an unrelated credential was missing | `withCredentials` aborts the whole stage on any missing credential ID | Migrations bind **only** the DB credential; OpenAI/Qdrant keys resolved optionally with a WARNING |
| 9 | Batch service checks failed spuriously | Stale `ERRORLEVEL`, `findstr` quirks, `timeout /t` needs a console, bare `npm` (a `.cmd`) ended the batch silently | `exit /b 0` guards, `ping` sleeps, `call npm`, health checks moved to `curl`; public/domain checks made WARNING-only |
| 10 | NSSM read-back verification failed repeatedly (`does NOT use localhost:5433`, `: was unexpected at this time`) | Batch `findstr`/substitution can't reliably parse the URL; a `.Contains()` check on wrapped output also mis-fired | PowerShell verification printing **only the host part** of the stored URL; final form runs **inline** (`powershell -Command`) after the generated `.ps1` file went missing on the target |
| 11 | `/health` returned `"db":"unavailable"` (async pool timeout) | Service-side DB config/connectivity, while sync (Alembic) path worked | Fixed the service environment to localhost (issue #3) and added the stored-URL verification (issue #10) so the log proves what the service uses |
| 12 | Nginx never listened on :8000 | (a) `nginx -t` judged by exit code — Windows returns rc=1 (shared-zone `Access is denied`) even when syntax is OK; (b) leftover `nginx.exe` master kept the old config; (c) server block could render conditionally | Judge `nginx -t` by **"syntax is ok" in stderr**; kill leftover masters; made the :8000 block **unconditional/literal** with a deploy-time assertion |
| 13 | Provisioning failed: `'knowledge_hub_backend_dir' is undefined` | Jenkins controller ran new role tasks with older role defaults | Inline `default(...)` fallbacks in the tasks + the `<project>-code` folder made dynamic from `project_name` (was hardcoded `copper-code`) |
| 14 | Frontend domain checks failed via `https://<domain>/` | No TLS and no :80/:443 listener exist in this setup | Domain checks go through Nginx on **`:8000`** (`http://<hostname>:8000/health`, `/mcp/tools`), WARNING-only |
| 15 | Gradle (legacy role) Chocolatey install returns 403 | Feed restriction on the pinned ancient version | Pre-existing; documented options (newer pinned version / internal feed) — unrelated to the Hub and left unchanged |

---

## 5. Change history (all merged to `main`)

35 pull requests, including: PG18+pgvector role (#1, #2, #6), Node18/Python312/Qdrant roles (#3), playbook wiring (#4), the Knowledge Hub pipeline and its fixes (#8–#24, #27–#31, #34, #35), the Nginx :8000 server and its hardening (#20, #23, #25, #26, #32, #33).

---

## 6. Final on-target confirmation checklist

The code is merged; these confirm the live deployment on each target:

```bat
netstat -ano | findstr ":5433 :6333 :8037 :8000 :6003"
sc query QASIP-KnowledgeHub
curl http://localhost:8037/health
curl http://localhost:8037/mcp/tools
curl -I http://localhost:8000/
curl http://<hostname>:8000/health
```

Expected: service RUNNING, `/health` answers with `"db":"ok"`, Admin UI loads at `http://<hostname>:8000/`.

**Known follow-ups (non-blocking):** create the `knowledgehub-openai-api-key` credential to enable LLM calls; consider Node 22 LTS when Node 18 reaches EOL; decide on the legacy Gradle/Chocolatey 403 (issue #15).
