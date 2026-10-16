# nginx-linux

Install and configure NGINX web server on Ubuntu Linux systems.

## Requirements

- Ubuntu Linux (Focal, Jammy, Noble)
- Ansible 2.9+

## Role Variables

None

## Dependencies

None

## Example Playbook

```yaml
- hosts: webservers
  roles:
    - nginx-linux
```

## Testing

To test this role locally:

```bash
cd test/roles/nginx-linux/tests/
ansible-playbook -i inventory test.yml
```

## License

GPL-2.0-or-later

## Author Information

your name
