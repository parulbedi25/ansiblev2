# Java Linux Role

This Ansible role installs multiple versions of OpenJDK on Linux systems.

## Features

- Installs multiple Java versions simultaneously
- Sets up JAVA_HOME for the default version
- Adds all Java versions to system PATH
- Supports Java versions: 8, 11, 17, 21

## Variables

### Default Variables (ansible/linux/roles/java-linux/defaults/main.yml)

```yaml
java_versions: ["8", "17"]        # List of Java versions to install
java_default_version: "17"        # Default Java version for JAVA_HOME
java_home: "/usr/lib/jvm/java-{{ java_default_version }}-openjdk-amd64"
```

### Variable Override Examples

Override variables using `-e` parameter in ansible-playbook command:

```bash
# Install Java 8 and 17, with 17 as default
ansible-playbook linux.yml -i inventory.ini -e "java_versions=['8','17']" -e "java_default_version='17'"

# Install Java 11 and 21, with 21 as default
ansible-playbook linux.yml -i inventory.ini -e "java_versions=['11','21']" -e "java_default_version='21'"

# Install only Java 17
ansible-playbook linux.yml -i inventory.ini -e "java_versions=['17']" -e "java_default_version='17'"
```

### Supported Java Versions

The role supports the following Java versions through the `java_packages` mapping:

- Java 8: `openjdk-8-jdk`
- Java 11: `openjdk-11-jdk`
- Java 17: `openjdk-17-jdk`
- Java 21: `openjdk-21-jdk`

## Usage

### Basic Usage

Run the main playbook with default settings (installs Java 8 and 17, defaults to 17):

```bash
ansible-playbook linux.yml -i inventory.ini
```

### Custom Java Versions

Install specific Java versions:

```bash
# Install Java 8, 11, and 17
ansible-playbook linux.yml -i inventory.ini -e "java_versions=['8','11','17']" -e "java_default_version='17'"

# Install only Java 21
ansible-playbook linux.yml -i inventory.ini -e "java_versions=['21']" -e "java_default_version='21'"
```

## What Gets Installed

1. **Multiple JDK Packages**: Installs OpenJDK packages for all specified versions
2. **JAVA_HOME**: Set to the default version's installation path
3. **PATH**: Updated to include bin directories for all installed Java versions
4. **Verification**: Checks installation of all Java versions and compilers

## Switching Between Java Versions

After installation, you can switch between Java versions using `update-alternatives`:

```bash
# List available Java alternatives
update-alternatives --list java

# Configure Java alternative
update-alternatives --config java

# Configure Javac alternative
update-alternatives --config javac
```

Or set specific versions in your shell:

```bash
# Use Java 8
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH

# Use Java 17
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH
```

## Example Output

When the role runs successfully, you'll see output like:

```
Java 8 version: openjdk version "1.8.0_XXX"
Java 17 version: openjdk version "17.0.X"
JAVA_HOME: /usr/lib/jvm/java-17-openjdk-amd64
Available Java alternatives:
  /usr/lib/jvm/java-17-openjdk-amd64/bin/java
  /usr/lib/jvm/java-8-openjdk-amd64/bin/java
```

## Testing

Run the role tests to verify multi-version Java installation:

```bash
# Run the role test playbook
ansible-playbook -i tests/inventory tests/test.yml

# Or test with different versions
ansible-playbook -i tests/inventory tests/test.yml -e "java_versions=['11','21']" -e "java_default_version='21'"
```

## Dependencies

- Ubuntu/Debian-based Linux distribution
- Ansible 2.9+
- Internet connection for package downloads

## Troubleshooting

1. **Package Not Found**: Ensure the Java version is supported and available in your Linux distribution's repositories
2. **Permission Issues**: Run Ansible with `become: yes` or as root
3. **PATH Issues**: After installation, you may need to log out and back in for PATH changes to take effect
4. **Multiple Versions**: All installed versions are available in PATH, with the default version first
