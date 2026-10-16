#!/bin/bash

set -e

echo "======================================="
echo "Stopping Services (if running)..."
echo "======================================="

# Systemd-managed services (service names match unit files created by Ansible)
sudo systemctl stop tomcat      2>/dev/null || true
sudo systemctl stop nginx       2>/dev/null || true
sudo systemctl stop couchdb     2>/dev/null || true
sudo systemctl stop redis       2>/dev/null || true  # Ansible creates "redis" not "redis-server"

# PostgreSQL is source-compiled; no systemd unit — stop via pg_ctl
PG_CTL="/usr/local/pgsql/bin/pg_ctl"
PG_DATA="/var/lib/postgresql/10/main"
if [ -f "$PG_CTL" ]; then
  sudo -u postgres "$PG_CTL" stop -D "$PG_DATA" -m fast 2>/dev/null || true
fi

echo "======================================="
echo "Disabling and Removing Systemd Service Units..."
echo "======================================="

for svc in tomcat nginx redis couchdb; do
  sudo systemctl disable "$svc" 2>/dev/null || true
done

sudo rm -f /etc/systemd/system/tomcat.service
sudo rm -f /etc/systemd/system/nginx.service
sudo rm -f /etc/systemd/system/redis.service
sudo systemctl daemon-reload

echo "======================================="
echo "Removing APT Installed Packages..."
echo "======================================="

# CouchDB installed via apt
sudo apt purge -y couchdb 2>/dev/null || true

# Java installed via apt (openjdk-8)
sudo apt purge -y "openjdk-*" 2>/dev/null || true

# Git installed via apt
sudo apt purge -y git 2>/dev/null || true

# Node/npm if any apt remnants
sudo apt purge -y nodejs npm 2>/dev/null || true

echo "======================================="
echo "Removing PostgreSQL (Source Install at /usr/local/pgsql)..."
echo "======================================="

sudo rm -rf /usr/local/pgsql
sudo rm -rf /var/lib/postgresql
sudo rm -rf /etc/postgresql
sudo rm -f  /tmp/postgresql-*.tar.gz
sudo rm -rf /tmp/postgresql-*/
sudo rm -f  /etc/profile.d/postgresql.sh
sudo rm -f  /usr/local/bin/postgres-start
sudo rm -f  /usr/local/bin/postgres-stop
sudo rm -f  /usr/local/bin/postgres-status
sudo userdel -r postgres 2>/dev/null || true

echo "======================================="
echo "Removing Redis (Source Install at /usr/local/redis)..."
echo "======================================="

sudo rm -rf /usr/local/redis
sudo rm -rf /usr/local/src/redis-*
sudo rm -f  /usr/local/bin/redis-server
sudo rm -f  /usr/local/bin/redis-cli
sudo rm -f  /usr/local/bin/redis-benchmark
sudo rm -f  /usr/local/bin/redis-check-aof
sudo rm -f  /usr/local/bin/redis-check-dump

echo "======================================="
echo "Removing Nginx (Source Install at /usr/local/nginx)..."
echo "======================================="

sudo rm -rf /usr/local/nginx
sudo rm -f  /usr/bin/nginx

echo "======================================="
echo "Removing Tomcat (Binary Install)..."
echo "======================================="

sudo rm -rf /opt/tomcat
sudo rm -rf /opt/apache-tomcat-*

echo "======================================="
echo "Removing Gradle (Binary Install at /opt/gradle-*)..."
echo "======================================="

sudo rm -rf /opt/gradle-*
sudo rm -f  /etc/profile.d/gradle.sh

echo "======================================="
echo "Removing Node.js / NVM (NVM Install at /usr/local/nvm)..."
echo "======================================="

sudo rm -rf /usr/local/nvm
sudo rm -f  /etc/profile.d/nvm.sh

echo "======================================="
echo "Removing Python 3.11 (Source Install via make altinstall)..."
echo "======================================="

sudo rm -f  /usr/local/bin/python3.11
sudo rm -f  /usr/local/bin/pip3.11
sudo rm -rf /usr/local/lib/python3.11
sudo rm -rf /usr/local/include/python3.11
sudo rm -rf /usr/src/Python-3.11*
sudo update-alternatives --remove python3 /usr/local/bin/python3.11 2>/dev/null || true

echo "======================================="
echo "Removing CouchDB Residuals..."
echo "======================================="

sudo rm -rf /opt/couchdb
sudo rm -rf /var/lib/couchdb
sudo rm -rf /etc/couchdb
sudo rm -f  /etc/apt/sources.list.d/couchdb.list
sudo rm -f  /usr/share/keyrings/couchdb-archive-keyring.gpg

echo "======================================="
echo "Cleaning Unused Packages and APT Cache..."
echo "======================================="

sudo apt autoremove -y
sudo apt autoclean

echo "======================================="
echo "Software Removal Completed Successfully"
echo "======================================="
