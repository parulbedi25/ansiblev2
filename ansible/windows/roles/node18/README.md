Role Name
=========

node18 - Node.js 18.20.8 on Windows, installed **side by side** with the
existing Node.js 10 from `roles/node`.

Why a separate role: `roles/node` installs Node 10 from the MSI into
`C:\Program Files\nodejs` and puts it on the machine PATH. An MSI install of
Node 18 would replace Node 10, which the existing services still need. This
role therefore installs Node 18 from the official ZIP distribution into
`D:\QASIP\Apps\node18` and leaves the machine PATH untouched.

Coexistence rules
-----------------

- Plain `node` / `npm` keep resolving to Node 10 (unchanged for existing services).
- New services (e.g. the Knowledge Hub frontend build) use Node 18 explicitly:
  `D:\QASIP\Apps\node18\node.exe`, `D:\QASIP\Apps\node18\npm.cmd` - or prepend
  `D:\QASIP\Apps\node18` to PATH inside their own build step.
- Set `node18_add_to_system_path: true` in `defaults/main.yml` only on a host
  dedicated to the new services (not recommended on shared hosts).

Role Variables
--------------

`defaults/main.yml`: `node18_version`, `node18_install_dir`,
`node18_add_to_system_path`. `vars/main.yml`: `node18_archive`, `node18_url`,
`node18_exe`, `node18_npm`.

Dependencies
------------

None. Not added to `windows.yml` automatically - add `node18` to a playbook's
roles when you want it.

Example Playbook
----------------

    - hosts: windows
      roles:
         - node18

License
-------

BSD
