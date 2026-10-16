# postgres14

Installs a **second** PostgreSQL instance — 14.24-4 by default, port **5433**,
with the **pgvector** extension — on a Windows host that already runs the
legacy PostgreSQL 10 instance (port 5432) from `ansible/windows/roles/postgres`.

That legacy instance is never modified: different install/data directories
(`D:\QASIP\Apps\postgres14`, `D:\QASIP\Data\postgres14`), a different Windows
service (`postgresql-x64-14`), no changes to the machine PATH for its binaries,
and a before/after health check that fails the run if PG 10's state changed.

See `../../README.md` for the full coexistence matrix, prerequisites (Visual
Studio C++ Build Tools for the pgvector `nmake` build) and run instructions.

Key variables (all in `defaults/main.yml`, all prefixed `pg14_`):
`pg14_version`, `pg14_port`, `pg14_install_dir`, `pg14_data_dir`,
`pg14_service_name`, `pg14_superuser_password`, `pg14_databases`,
`pg14_roles`, `pg14_pgvector_enabled`, `pg14_pgvector_version`,
`pg14_pgvector_install_method` (`build` | `prebuilt` | `none`),
`pg14_open_firewall`, `pg14_create_cli_wrappers`.

Requirements: Ansible ≥ 2.15 with the `ansible.windows` and `community.windows`
collections; a Windows target reachable over WinRM.
