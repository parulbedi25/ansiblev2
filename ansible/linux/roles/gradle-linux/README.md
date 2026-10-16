# gradle-linux

Install Gradle build tool from source on Ubuntu Linux systems.

## Requirements

- Ubuntu Linux (Focal, Jammy, Noble)
- Ansible 2.9+
- Java 8+ (automatically installed)

## Role Variables

- `gradle_version`: Gradle version to install (default: "2.6")
- `gradle_archive`: Archive filename (default: "gradle-{{ gradle_version }}-all.zip")
- `gradle_url`: Download URL (default: "https://services.gradle.org/distributions/{{ gradle_archive }}")
- `gradle_install_dir`: Installation directory (default: "/opt/gradle-{{ gradle_version }}")

## Dependencies

None

## Example Playbook

```yaml
- hosts: developers
  roles:
    - gradle-linux
```

## Testing

To test this role locally:

```bash
cd test/roles/gradle-linux/tests/
ansible-playbook -i inventory test.yml
```

## Handlers

This role uses handlers for system configuration:

- `update profile`: Placeholder for profile updates

## License

GPL-2.0-or-later

## Author Information

your name
