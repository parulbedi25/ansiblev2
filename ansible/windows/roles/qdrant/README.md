Role Name
=========

qdrant - Qdrant vector database (new tool, required by the Knowledge Hub
service) on Windows. Installed from the official GitHub release ZIP and run
as a Windows service via NSSM - the same pattern as `roles/node-service`.

Configuration produced:

- Binary: `D:\QASIP\Apps\qdrant\qdrant.exe` (Qdrant 1.19.2)
- Service: `QASIP-Qdrant`, automatic, restarts on failure
- HTTP port **6333**, gRPC port **6334** (firewall rule `qdrant-tcp-6333`)
- **Persistent storage**: `D:\QASIP\Data\qdrant\storage`, snapshots in
  `D:\QASIP\Data\qdrant\snapshots` - data survives restarts/reboots
- Config: `D:\QASIP\Apps\qdrant\config\config.yaml` (from `templates/config.yaml.j2`)
- Logs: `D:\QASIP\Apps\qdrant\logs\stdout.log` / `stderr.log` (NSSM rotation)

The backend connects with `QASIP_HUB_QDRANT_URL=http://<this-host>:6333`.
If `qdrant_api_key` is set (do it via `secrets.yml` / Jenkins, not in git),
the same value must be set as `QASIP_HUB_QDRANT_API_KEY` for the backend.

Requirements
------------

NSSM must be installed first (`roles/nssm`, already ordered before this in
`windows.yml`). Outbound access to `github.com` for the release ZIP, or
pre-stage the ZIP in `D:\temp`.

Role Variables
--------------

`defaults/main.yml`: `qdrant_version`, `qdrant_install_dir`,
`qdrant_storage_dir`, `qdrant_snapshots_dir`, `qdrant_http_port`,
`qdrant_grpc_port`, `qdrant_service_name`, `qdrant_api_key`,
`qdrant_open_firewall`. `vars/main.yml`: `qdrant_archive`, `qdrant_url`,
`qdrant_exe`, `qdrant_config_file`.

Dependencies
------------

None declared - run `roles/nssm` before this role. Not added to
`windows.yml` automatically; add `qdrant` to a playbook's roles to use it.

Example Playbook
----------------

    - hosts: windows
      roles:
         - nssm
         - qdrant

License
-------

BSD
