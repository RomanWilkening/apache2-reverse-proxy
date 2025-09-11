#!/bin/bash
set -euo pipefail

echo "Starting Apache2 Reverse Proxy with Let's Encrypt support..."

# Apache2 Verzeichnisse erstellen falls nicht vorhanden
mkdir -p ${APACHE_RUN_DIR}
mkdir -p ${APACHE_LOCK_DIR}
mkdir -p ${APACHE_LOG_DIR}

# Berechtigungen setzen
chown -R ${APACHE_RUN_USER}:${APACHE_RUN_GROUP} ${APACHE_LOG_DIR}
chown -R ${APACHE_RUN_USER}:${APACHE_RUN_GROUP} /var/www/html

# Seed-on-empty für Apache-Konfigurationsverzeichnisse bei Bind-Mounts
seed_if_empty() {
    local source_dir="$1"
    local target_dir="$2"
    if [ ! -d "$target_dir" ]; then
        mkdir -p "$target_dir"
    fi
    if [ -z "$(ls -A "$target_dir" 2>/dev/null || true)" ]; then
        echo "Initializing $target_dir from $source_dir ..."
        # -a bewahrt Rechte/Links, der Punkt kopiert nur Inhalte, nicht das Verzeichnis selbst
        cp -a "$source_dir"/. "$target_dir"/
    else
        echo "$target_dir not empty, leaving as-is."
    fi
}

DEFAULTS_ROOT="/opt/defaults/apache2"
seed_if_empty "$DEFAULTS_ROOT/sites-available" "/etc/apache2/sites-available"
seed_if_empty "$DEFAULTS_ROOT/sites-enabled" "/etc/apache2/sites-enabled"
seed_if_empty "$DEFAULTS_ROOT/conf-available" "/etc/apache2/conf-available"
seed_if_empty "$DEFAULTS_ROOT/conf-enabled" "/etc/apache2/conf-enabled"
seed_if_empty "$DEFAULTS_ROOT/mods-available" "/etc/apache2/mods-available"
seed_if_empty "$DEFAULTS_ROOT/mods-enabled" "/etc/apache2/mods-enabled"

# Falls nach Seeding noch keine Site aktiviert ist, minimale Default-Site erstellen
if [ -z "$(ls -A /etc/apache2/sites-enabled 2>/dev/null || true)" ]; then
    echo "No enabled sites found. Creating minimal default vhost..."
    cat > /etc/apache2/sites-enabled/000-default.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined

    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
fi

# Apache2 Konfiguration testen
echo "Testing Apache2 configuration..."
apache2ctl configtest

# Cron für Let's Encrypt starten
echo "Starting cron for Let's Encrypt auto-renewal..."
service cron start

# ServerName setzen falls nicht vorhanden
if ! grep -q "^ServerName" /etc/apache2/apache2.conf; then
    echo "ServerName localhost" >> /etc/apache2/apache2.conf
fi

# Execute CMD
echo "Starting Apache2..."
exec "$@"