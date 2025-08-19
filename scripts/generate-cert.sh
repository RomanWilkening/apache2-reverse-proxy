#!/bin/bash
# Hilfsskript zum Generieren von Let's Encrypt Zertifikaten

set -e

# Prüfe ob Parameter übergeben wurden
if [ $# -eq 0 ]; then
    echo "Verwendung: $0 <domain> [zusätzliche-domains...]"
    echo "Beispiel: $0 example.com www.example.com"
    exit 1
fi

# Container Name
CONTAINER_NAME="apache-reverse-proxy"

# Prüfe ob Container läuft
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo "Error: Container '$CONTAINER_NAME' läuft nicht!"
    exit 1
fi

# Domains sammeln
DOMAINS=""
for domain in "$@"; do
    DOMAINS="$DOMAINS -d $domain"
done

echo "Generiere Zertifikat für: $DOMAINS"
echo "Bitte stellen Sie sicher, dass alle Domains auf diesen Server zeigen!"
echo ""

# Certbot ausführen
docker exec -it $CONTAINER_NAME certbot --apache \
    --non-interactive \
    --agree-tos \
    --email webmaster@${1} \
    --no-eff-email \
    $DOMAINS

echo ""
echo "Zertifikat wurde erfolgreich erstellt!"
echo "Apache wurde automatisch neu konfiguriert."