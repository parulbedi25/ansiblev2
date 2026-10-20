Role Name
=========

python312 - Python 3.12.10 on Windows, installed **side by side** with the
existing Python 3.11 from `roles/python`.

Python installers keep each version line in its own directory, so 3.12 goes
to `C:\Program Files\Python312` and never overwrites `Python311`. Unlike
`roles/python`, this role does **not** prepend itself to PATH - plain
`python` keeps meaning Python 3.11 for the existing services.

Selecting a version (for the new services, e.g. Knowledge Hub backend):

    py -0p                                   # list all installed Pythons
    py -3.12 -m venv .venv                   # create a 3.12 virtualenv
    C:\Program Files\Python312\python.exe --version

Role Variables
--------------

`defaults/main.yml`: `python312_version`, `python312_install_dir`,
`python312_prepend_path` (keep `false` on shared hosts).
`vars/main.yml`: `python312_installer`, `python312_url`, `python312_exe`.

Dependencies
------------

None. Not added to `windows.yml` automatically - add `python312` to a
playbook's roles when you want it.

Example Playbook
----------------

    - hosts: windows
      roles:
         - python312

License
-------

BSD
