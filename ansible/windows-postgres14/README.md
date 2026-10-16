# PostgreSQL 14 (second instance) for Windows — `windows-postgres14/`

A **separate, self-contained** Ansible setup that installs a second PostgreSQL
instance — **PostgreSQL 14.24-4** with the **pgvector** extension — next to the
existing PostgreSQL 10 instance, for the services that need PostgreSQL 14+.

Nothing in the existing tree is modified: `ansible/windows/windows.yml`,
`ansible/windows/roles/postgres/` (PG 10), the inventories, secrets and every
Jenkinsfile keep working exactly as they do today.

## What gets installed

| | Existing (untouched) | New (this tree) |
|---|---|---|
| PostgreSQL | 10.17-2 | **14.24-4** |
| Installer | `postgresql-10.17-2-windows-x64.exe` | `postgresql-14.24-4-windows-x64.exe` |
| Download | get.enterprisedb.com | <https://get.enterprisedb.com/postgresql/postgresql-14.24-4-windows-x64.exe> |
| Install dir | `D:\QASIP\Apps\postgres` | `D:\QASIP\Apps\postgres14` |
| Data dir | `D:\QASIP\Data\postgres` | `D:\QASIP\Data\postgres14` |
| Service | `postgresql-x64-10` | `postgresql-x64-14` |
| Port | 5432 | **5433** |
| Extensions | — | **pgvector 0.8.7** (`CREATE EXTENSION vector`) |
| Client tools | `psql`, `pg_dumpall`, … from PG 10's `bin` on PATH | `psql14`, `pg_dump14`, `pg_dumpall14`, `pg_restore14`, `postgres14-status` |
| Firewall | — | new rule `postgres14-tcp-5433` (inbound TCP 5433) |
| Databases / roles | `atms_master`, `admin`, `developer`, `app`, `report` | same names, created **inside the new instance** |

Password note: the new instance is deliberately given the same superuser name
(`postgres`) and, via `secrets.yml` here, the same password as PG 10 so the
team keeps one credential to remember. It is still a separate server — change
`secrets.yml` in this directory (and vault-encrypt it) if you want it different.

## ⚠️ PostgreSQL 14 end-of-life

PostgreSQL 14 is the last 14.x line and reaches **end-of-life on 2026-11-12**.
14.24-4 is what you asked for ("14+"), and this installs exactly that — but if
"14 or newer" is the real requirement, prefer **16.15-5** or **17.9-2**: change
one line (`pg14_version` in `roles/postgres14/defaults/main.yml`) and the
install dir, data dir, service name (`postgresql-x64-16`/`-17`), wrappers
(`psql16`, …) and pgvector build all follow automatically. The port stays 5433.

## Prerequisites on the target Windows host

1. WinRM reachable, same as the existing playbooks (`[windows]` group, port 5985).
2. Internet access to `get.enterprisedb.com` (installer) and `github.com`
   (pgvector source) — or pre-stage both files.
3. **Visual Studio C++ Build Tools** — only needed for pgvector. pgvector ships
   no official Windows binaries, so it is compiled with `nmake` against the new
   install (`PGROOT=D:\QASIP\Apps\postgres14`). Free, no IDE required:
   `winget install Microsoft.VisualStudio.2022.BuildTools` + the
   *"Desktop development with C++"* workload. If the tools are missing the run
   stops after PostgreSQL itself is installed and tells you exactly this.
   Prefer not to compile on the server? Build once anywhere and set
   `pg14_pgvector_install_method: prebuilt` + `pg14_pgvector_prebuilt_url`
   (a ZIP containing `lib\vector.dll` and `share\extension\vector*`).

## Run it

From the repository root, reusing the inventory you already have:

```bat
ansible-playbook ansible/windows-postgres14/postgres14.yml ^
  -i ansible/windows/inventory/inventory.ini
```

or with this tree's own inventory (`inventory/inventory.ini`, or render
`inventory.ini.j2` with `ANSIBLE_IP_ADDRESS` / `ANSIBLE_USER` /
`ANSIBLE_PASSWORD` exactly like `Jenkinsfile-provision-windows`).

Useful overrides:

```bat
REM different port / password, nothing else changes
ansible-playbook ansible/windows-postgres14/postgres14.yml ^
  -i ansible/windows/inventory/inventory.ini ^
  -e "pg14_port=5434" -e "pg14_superuser_password=..."

REM skip pgvector, or install it from a pre-built ZIP instead of compiling
  -e "pg14_pgvector_enabled=false"
  -e "pg14_pgvector_install_method=prebuilt" -e "pg14_pgvector_prebuilt_url=https://.../pgvector.zip"
```

To wire it into Jenkins later, copy the pattern from
`Jenkinsfile-provision-windows` (render `inventory.ini.j2`, then
`ansible-playbook ansible/windows-postgres14/postgres14.yml -i ... -e "@$VARS_FILE"`)
with `pg14_superuser` / `pg14_superuser_password` in the JSON. No existing
Jenkinsfile needs to change.

## How PG 10 is protected

* **Different everything** — port, install dir, data dir, service name,
  variable names (`pg14_*` vs `pg_*`) and firewall rule name. The role asserts
  all of these differ before it changes anything.
* **Explicit paths only** — every `psql` call is
  `D:\QASIP\Apps\postgres14\bin\psql.exe -p 5433`. (The legacy role *searches*
  the disk for the first `psql.exe`; with two installs that is ambiguous, so
  this role never does it.)
* **Identity check** — after install it reads `PG_VERSION` and asks the server
  for `server_version`, `port` and `data_directory`, and aborts if the answers
  don't prove it is talking to the new instance.
* **PATH is not polluted** — PG 14's `bin` never goes on the machine PATH, so
  the existing backup job (`Jenkinsfile-db-backup-windows`, `pg_dumpall` on
  5432) and any script calling plain `psql` keep resolving to PG 10. Use the
  `…14`-suffixed wrappers for the new instance.
* **Before/after proof** — the role snapshots the PG 10 service state and
  port 5432 listener before it starts and re-checks them at the end; the final
  summary prints both instances side by side.
* **Idempotent** — re-running does not reinstall, does not recreate existing
  databases/roles, and only restarts the PG 14 service if its config changed.

## Layout

```
windows-postgres14/
├── postgres14.yml            standalone playbook (hosts: windows, role: postgres14)
├── secrets.yml               pg14_superuser / pg14_superuser_password (vault this)
├── inventory/
│   ├── inventory.ini         sample inventory
│   └── inventory.ini.j2      Jenkins-style rendered inventory
└── roles/postgres14/
    ├── defaults/main.yml     every knob, all pg14_* (version, port, paths, pgvector…)
    ├── vars/main.yml         derived paths/URL for the installer
    ├── handlers/main.yml     restart/ensure-running for postgresql-x64-14 only
    ├── tasks/main.yml        preflight → install → verify → configure →
    │                         provision → pgvector → wrappers → firewall → final check
    ├── templates/cli_wrapper.bat.j2
    └── tests/                syntax-check inventory + playbook
```
