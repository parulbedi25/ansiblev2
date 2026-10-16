# couchdb-linux

Install and configure Apache CouchDB on Ubuntu Linux systems.

## Requirements

- Ubuntu Linux (Focal, Jammy, Noble)
- Ansible 2.9+

## Role Variables

- `couchdb_admin_password`: Admin password for CouchDB (default: "admin123")
- `couchdb_bind_address`: Bind address for CouchDB (default: "0.0.0.0")
- `couchdb_port`: Port for CouchDB (default: 5984)

## Dependencies

None

## Example Playbook

```yaml
- hosts: databases
  roles:
    - couchdb-linux
```

## Testing

To test this role locally:

```bash
cd test/roles/couchdb-linux/tests/
ansible-playbook -i inventory test.yml
```

## Handlers

This role uses handlers for service management:

- `restart couchdb`: Restarts CouchDB service
- `reload couchdb`: Reloads CouchDB configuration
- `start couchdb`: Starts and enables CouchDB service
- `stop couchdb`: Stops CouchDB service

## License

GPL-2.0-or-later

## Author Information

your name
