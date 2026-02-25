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

# DynDNS Konfiguration seed-on-empty
DYNDNS_DEFAULTS_ROOT="/opt/defaults/dyndns"
if [ -d "$DYNDNS_DEFAULTS_ROOT" ]; then
    seed_if_empty "$DYNDNS_DEFAULTS_ROOT" "/etc/dyndns"
    if [ ! -f "/etc/dyndns/config.env" ] && [ -f "$DYNDNS_DEFAULTS_ROOT/config.env.example" ]; then
        cp "$DYNDNS_DEFAULTS_ROOT/config.env.example" "/etc/dyndns/config.env"
        echo "DynDNS: /etc/dyndns/config.env aus Beispiel erzeugt."
    fi
fi

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
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
fi

# Apache2 Konfiguration testen
echo "Testing Apache2 configuration..."
apache2ctl configtest

# DynDNS Cron einrichten (vor Cron-Start)
if [ -f "/etc/dyndns/config.env" ]; then
    echo "Config für DynDNS gefunden. Richte Cronjob ein..."
    CRON_SCHEDULE="*/5 * * * *"
    if grep -qE '^DYNDNS_CRON=' /etc/dyndns/config.env; then
        CRON_SCHEDULE=$(grep -E '^DYNDNS_CRON=' /etc/dyndns/config.env | cut -d'=' -f2-)
    fi
    # Cron versteht keine */5 Sekunden. Emuliere 5s-Intervall via * * * * * und sleep 5 Schleife.
    if [ "$CRON_SCHEDULE" = "*/5 * * * *" ] || [ "$CRON_SCHEDULE" = "* * * * * */5" ]; then
        # Falls gewünscht: echte 5 Sekunden – implementiere über fünf Einträge mit sleep
        {
            echo "* * * * * root /usr/local/bin/dyndns-updater.sh >> /proc/1/fd/1 2>> /proc/1/fd/2" 
            echo "* * * * * root sleep 5; /usr/local/bin/dyndns-updater.sh >> /proc/1/fd/1 2>> /proc/1/fd/2"
            echo "* * * * * root sleep 10; /usr/local/bin/dyndns-updater.sh >> /proc/1/fd/1 2>> /proc/1/fd/2"
            echo "* * * * * root sleep 15; /usr/local/bin/dyndns-updater.sh >> /proc/1/fd/1 2>> /proc/1/fd/2"
            echo "* * * * * root sleep 20; /usr/local/bin/dyndns-updater.sh >> /proc/1/fd/1 2>> /proc/1/fd/2"
            echo "* * * * * root sleep 25; /usr/local/bin/dyndns-updater.sh >> /proc/1/fd/1 2>> /proc/1/fd/2"
            echo "* * * * * root sleep 30; /usr/local/bin/dyndns-updater.sh >> /proc/1/fd/1 2>> /proc/1/fd/2"
            echo "* * * * * root sleep 35; /usr/local/bin/dyndns-updater.sh >> /proc/1/fd/1 2>> /proc/1/fd/2"
            echo "* * * * * root sleep 40; /usr/local/bin/dyndns-updater.sh >> /proc/1/fd/1 2>> /proc/1/fd/2"
            echo "* * * * * root sleep 45; /usr/local/bin/dyndns-updater.sh >> /proc/1/fd/1 2>> /proc/1/fd/2"
            echo "* * * * * root sleep 50; /usr/local/bin/dyndns-updater.sh >> /proc/1/fd/1 2>> /proc/1/fd/2"
            echo "* * * * * root sleep 55; /usr/local/bin/dyndns-updater.sh >> /proc/1/fd/1 2>> /proc/1/fd/2"
        } > /etc/cron.d/dyndns-update
    else
        echo "${CRON_SCHEDULE} root /usr/local/bin/dyndns-updater.sh >> /proc/1/fd/1 2>> /proc/1/fd/2" > /etc/cron.d/dyndns-update
    fi
    chmod 0644 /etc/cron.d/dyndns-update
    echo "DynDNS: führe initiales Update aus..."
    /usr/local/bin/dyndns-updater.sh || true
else
    echo "Keine DynDNS-Konfiguration vorhanden (überspringe)."
fi

# Cron für Let's Encrypt und DynDNS starten
echo "Starting cron for renewals and dyndns..."
service cron start

# ServerName setzen falls nicht vorhanden
if ! grep -q "^ServerName" /etc/apache2/apache2.conf; then
    echo "ServerName localhost" >> /etc/apache2/apache2.conf
fi

# Execute CMD
echo "Starting Apache2..."
exec "$@"
