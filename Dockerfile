# Basis-Image: Ubuntu 22.04 LTS (minimal)
FROM ubuntu:22.04

# Environment Variables
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Update und Installation der benötigten Pakete
RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2 \
    apache2-utils \
    certbot \
    python3-certbot-apache \
    curl \
    ca-certificates \
    tzdata \
    cron \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Apache Module aktivieren
RUN a2enmod proxy \
    && a2enmod proxy_http \
    && a2enmod ssl \
    && a2enmod rewrite \
    && a2enmod headers \
    && a2enmod proxy_wstunnel \
    && a2enmod proxy_connect

# Verzeichnisse für Bind-Mounts erstellen
RUN mkdir -p /etc/apache2/sites-available \
    && mkdir -p /etc/apache2/sites-enabled \
    && mkdir -p /etc/letsencrypt \
    && mkdir -p /var/log/apache2 \
    && mkdir -p /var/www/html

# Standard Apache Konfiguration entfernen
RUN rm -f /etc/apache2/sites-enabled/000-default.conf

# Defaults der Apache-Konfiguration für Seed-on-empty sichern
RUN mkdir -p /opt/defaults/apache2 \
    && cp -a /etc/apache2/sites-available /opt/defaults/apache2/ \
    && cp -a /etc/apache2/sites-enabled /opt/defaults/apache2/ \
    && cp -a /etc/apache2/conf-available /opt/defaults/apache2/ \
    && cp -a /etc/apache2/conf-enabled /opt/defaults/apache2/ \
    && cp -a /etc/apache2/mods-available /opt/defaults/apache2/ \
    && cp -a /etc/apache2/mods-enabled /opt/defaults/apache2/

# Cron für Let's Encrypt Auto-Renewal
RUN echo "0 0,12 * * * root certbot renew --quiet --no-self-upgrade --post-hook 'apache2ctl graceful'" > /etc/cron.d/certbot-renew \
    && chmod 0644 /etc/cron.d/certbot-renew

# Entrypoint-Skript kopieren
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Apache2 Foreground Mode konfigurieren
ENV APACHE_RUN_USER www-data
ENV APACHE_RUN_GROUP www-data
ENV APACHE_LOG_DIR /var/log/apache2
ENV APACHE_PID_FILE /var/run/apache2/apache2.pid
ENV APACHE_RUN_DIR /var/run/apache2
ENV APACHE_LOCK_DIR /var/lock/apache2

# Ports
EXPOSE 80 443

# Health Check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

# Entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["apache2ctl", "-D", "FOREGROUND"]