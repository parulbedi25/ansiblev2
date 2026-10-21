Role Name
=========

postgres14 - PostgreSQL 18.24-4 on Windows, running as a second instance
beside the existing PostgreSQL 10 role (`roles/postgres`). It is a replica of
that role with the same file structure and approach, configured with:

- installer `postgresql-14.24-4-windows-x64.exe` (get.enterprisedb.com)
- install dir `D:\QASIP\Apps\postgres14`, data dir `D:\QASIP\Data\postgres14`
- service `postgresql-x64-18`, port **5433** (PostgreSQL 10 keeps 5432)
- databases `atms_master` and `qasip_hub`, roles `admin`, `developer`, `app`, `report`
- pgvector extension enabled in both databases

Deliberate differences from `roles/postgres`, so the two instances coexist:

- all variables are prefixed `pg14_` (no clash with `pg_*`)
- pgAdmin: the **latest standalone pgAdmin 4 (9.18)** is installed/upgraded
  from the official postgresql.org installer. The pgAdmin bundled with old
  EDB installers crashes on launch with a fatal error; the standalone
  installer replaces/upgrades it. One pgAdmin serves both PostgreSQL 10
  (port 5432) and this instance (port 5433) - add each as a server in pgAdmin.
  Disable with `pg14_pgadmin_enabled: false`, pin via `pg14_pgadmin_version`.
- the PostgreSQL 18 `bin` directory is **not** added to the system PATH -
  plain `psql` / `pg_dumpall` keep resolving to PostgreSQL 10. Use the full
  paths (`pg14_psql_path`, `pg14_dumpall_path`) or port 5433 explicitly.

Requirements
------------

Windows target reachable over WinRM. For pgvector: `git` to fetch the
pgvector source, and the Visual Studio C++ Build Tools that are part of
the base Windows image (pgvector has no official Windows binaries; on
Windows the `make` / `make install` step is
`nmake /F Makefile.win` + `nmake /F Makefile.win install`, run by
`templates/pgvector_build.bat.j2` after loading `vcvars64.bat`).
This role does not install the Build Tools - it only locates
`vcvars64.bat` (override with `pg14_pgvector_vcvars_path`).
Set `pg14_pgvector_enabled: false` to skip pgvector.

Role Variables
--------------

See `defaults/main.yml` (`pg14_version`, `pg14_port`, `pg14_superuser`,
`pg14_superuser_password`, `pg14_db_names`, `pg14_roles`,
`pg14_pgvector_enabled`, `pg14_pgvector_version`) and `vars/main.yml`
(`pg14_installer`, `pg14_url`, `pg14_install_dir`, `pg14_data_dir`,
`pg14_service_name`).

Dependencies
------------

None. This role is not added to `windows.yml` automatically - add
`postgres14` to a playbook's roles when you want to run it.

Example Playbook
----------------

    - hosts: windows
      roles:
         - postgres14

License
-------

BSD

Author Information
------------------

Replica of `roles/postgres`, adapted for PostgreSQL 18.
