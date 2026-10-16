# PostgreSQL Linux Role

This Ansible role installs PostgreSQL 10.17 from source code on Linux systems, following the same installation process as the provided bash script.

## Features

- Compiles and installs PostgreSQL 10.17 from source
- Creates dedicated postgres user and directories
- Sets up environment variables and PATH
- Configures PostgreSQL for remote access
- Creates database and sets admin password
- Provides helper scripts for service management
- Includes comprehensive verification steps

## Variables

### Default Variables (ansible/linux/roles/postgres-linux/defaults/main.yml)

```yaml
postgresql_version: "10.17"
postgresql_admin_user: "postgres"
postgresql_admin_password: "admin"
postgresql_database: "atm_master"
postgresql_port: 5432
postgresql_listen_addresses: "*"
postgresql_install_dir: "/usr/local/pgsql"
postgresql_data_dir: "/var/lib/postgresql/{{ postgresql_version.split('.')[0] }}/main"
postgresql_log_dir: "/var/lib/postgresql/{{ postgresql_version.split('.')[0] }}/logs"
postgresql_source_url: "https://ftp.postgresql.org/pub/source/v{{ postgresql_version }}/postgresql-{{ postgresql_version }}.tar.gz"
```

### Variable Override Examples

Override variables using `-e` parameter in ansible-playbook command:

```bash
# Install PostgreSQL with custom database name
ansible-playbook linux.yml -i inventory.ini -e "postgresql_database='myapp_db'"

# Install PostgreSQL with custom password
ansible-playbook linux.yml -i inventory.ini -e "postgresql_admin_password='secure_password'"

# Install PostgreSQL with custom port
ansible-playbook linux.yml -i inventory.ini -e "postgresql_port='5433'"
```

## Installation Process

The role follows the same 11-step process as the bash script:

1. **Install Dependencies**: Build tools, libraries, and development packages
2. **Download Source**: PostgreSQL 10.17 source code from official repository
3. **Extract Source**: Unpack the downloaded tarball
4. **Configure Build**: Run `./configure` with custom options
5. **Compile**: Build PostgreSQL (takes 5-10 minutes)
6. **Install**: Install binaries and contrib modules
7. **Create User & Directories**: Set up postgres user and data directories
8. **Setup Environment**: Configure PATH and LD_LIBRARY_PATH
9. **Initialize Database**: Create PostgreSQL data cluster
10. **Configure PostgreSQL**: Set up pg_hba.conf and postgresql.conf
11. **Start Service**: Launch PostgreSQL and create database

## What Gets Installed

1. **PostgreSQL 10.17**: Compiled from source in `/usr/local/pgsql`
2. **Database Cluster**: Initialized in `/var/lib/postgresql/10/main`
3. **Log Directory**: Created at `/var/lib/postgresql/10/logs`
4. **Environment Setup**: PATH and library paths configured
5. **Helper Scripts**: `postgres-start`, `postgres-stop`, `postgres-status`
6. **Database**: `atm_master` database created with admin user

## Usage

### Basic Usage

Run the main playbook with default settings:

```bash
ansible-playbook linux.yml -i inventory.ini
```

### Custom Configuration

Install with custom database settings:

```bash
ansible-playbook linux.yml -i inventory.ini \
  -e "postgresql_database='production_db'" \
  -e "postgresql_admin_password='secure123'" \
  -e "postgresql_port='5433'"
```

## Service Management

After installation, use the provided helper scripts:

```bash
# Start PostgreSQL
postgres-start

# Stop PostgreSQL
postgres-stop

# Check status
postgres-status

# Connect to database
sudo -u postgres /usr/local/pgsql/bin/psql -d atm_master
```

Or use direct pg_ctl commands:

```bash
# Start
sudo -u postgres /usr/local/pgsql/bin/pg_ctl start -D /var/lib/postgresql/10/main -l /var/lib/postgresql/10/logs/postgresql.log

# Stop
sudo -u postgres /usr/local/pgsql/bin/pg_ctl stop -D /var/lib/postgresql/10/main

# Status
sudo -u postgres /usr/local/pgsql/bin/pg_ctl status -D /var/lib/postgresql/10/main
```

## Configuration Files

### pg_hba.conf
- Allows local connections with trust authentication
- Enables MD5 password authentication for remote connections
- Configures replication settings

### postgresql.conf
- Sets listen_addresses to allow remote connections
- Configures port (default: 5432)
- Sets memory parameters and logging options
- Configures locale and timezone settings

## Database Access

After installation:

- **Host**: localhost or remote IP
- **Port**: 5432 (configurable)
- **Database**: atm_master
- **User**: postgres
- **Password**: admin (configurable)
- **Connection**: `psql -h localhost -p 5432 -U postgres -d atm_master`

## Testing

Run the role tests to verify PostgreSQL installation:

```bash
# Test the role directly
ansible-playbook -i tests/inventory tests/test.yml

# Test with custom variables
ansible-playbook -i tests/inventory tests/test.yml -e "postgresql_database='test_db'"
```

## Dependencies

- Ubuntu/Debian-based Linux distribution
- Ansible 2.9+
- Internet connection for downloading source code
- Build tools (gcc, make, etc.)
- Development libraries (readline, zlib, openssl, etc.)

## Troubleshooting

1. **Compilation Fails**: Ensure all build dependencies are installed
2. **Permission Issues**: Run Ansible with `become: yes`
3. **Port Conflicts**: Check if port 5432 is already in use
4. **Environment Issues**: Source `/etc/profile.d/postgresql.sh` or log out/in
5. **Connection Issues**: Verify `listen_addresses` and `pg_hba.conf` settings

## Security Notes

- Default password is "admin" - change in production
- Remote access is enabled by default (`listen_addresses = "*"`)
- Consider restricting `pg_hba.conf` for production use
- The installation allows password authentication for remote connections

## File Locations

- **Binaries**: `/usr/local/pgsql/bin/`
- **Data**: `/var/lib/postgresql/10/main/`
- **Logs**: `/var/lib/postgresql/10/logs/postgresql.log`
- **Config**: `/var/lib/postgresql/10/main/postgresql.conf`
- **Auth Config**: `/var/lib/postgresql/10/main/pg_hba.conf`
- **Environment**: `/etc/profile.d/postgresql.sh`
- **Helper Scripts**: `/usr/local/bin/postgres-*`
