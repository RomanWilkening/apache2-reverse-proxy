#!/bin/bash
set -e

echo "Starting Apache2 Reverse Proxy with Let's Encrypt support..."

# Apache2 Verzeichnisse erstellen falls nicht vorhanden
mkdir -p ${APACHE_RUN_DIR}
mkdir -p ${APACHE_LOCK_DIR}
mkdir -p ${APACHE_LOG_DIR}

# Berechtigungen setzen
chown -R ${APACHE_RUN_USER}:${APACHE_RUN_GROUP} ${APACHE_LOG_DIR}
chown -R ${APACHE_RUN_USER}:${APACHE_RUN_GROUP} /var/www/html

# Prüfen ob sites-enabled leer ist
if [ -z "$(ls -A /etc/apache2/sites-enabled)" ]; then
    echo "Warnung: Keine Sites aktiviert. Bitte mounten Sie Ihre Konfigurationsdateien."
    # Erstelle eine minimale Default-Konfiguration
    cat > /etc/apache2/sites-enabled/000-default.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
    
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