# Apache2 Reverse Proxy mit Let's Encrypt

Dieses Docker-Image bietet einen Apache2 Reverse Proxy basierend auf Ubuntu 22.04 LTS mit integrierter Let's Encrypt Unterstützung.

## Features

- **Minimales Ubuntu 22.04 LTS** als Basis
- **Apache2** mit allen wichtigen Proxy-Modulen
- **Let's Encrypt** Integration mit automatischer Zertifikatserneuerung
- **Bind-Mount** Unterstützung für alle Konfigurationsdateien
- **Portainer** kompatibel
- **Einfache Updates** ohne Konfigurationsverlust

## Schnellstart

### 1. Repository klonen

```bash
git clone <repository-url>
cd apache-reverse-proxy
```

### 2. Konfiguration vorbereiten

Die Apache-Konfiguration wird über Bind-Mounts eingebunden. Die Verzeichnisstruktur ist bereits vorbereitet:

```
config/
├── sites-available/    # Verfügbare Site-Konfigurationen
├── sites-enabled/      # Aktivierte Sites (Symlinks)
├── conf-available/     # Zusätzliche Apache-Konfigurationen
├── conf-enabled/       # Aktivierte Konfigurationen
├── mods-available/     # Module-Konfigurationen
└── mods-enabled/       # Aktivierte Module
```

### 3. Reverse Proxy konfigurieren

1. Kopieren Sie eine der Beispielkonfigurationen:
```bash
cp config/sites-available/example-reverse-proxy.conf config/sites-available/meine-domain.conf
```

2. Passen Sie die Konfiguration an Ihre Bedürfnisse an (Domain, Backend-Server, etc.)

3. Aktivieren Sie die Site:
```bash
cd config/sites-enabled/
ln -s ../sites-available/meine-domain.conf .
```

### 4. Container starten

Mit Docker Compose:
```bash
docker-compose up -d
```

Oder direkt mit Docker:
```bash
docker build -t apache-reverse-proxy .
docker run -d \
  --name apache-reverse-proxy \
  -p 80:80 \
  -p 443:443 \
  -v $(pwd)/config/sites-available:/etc/apache2/sites-available:ro \
  -v $(pwd)/config/sites-enabled:/etc/apache2/sites-enabled:ro \
  -v letsencrypt:/etc/letsencrypt \
  -v $(pwd)/logs:/var/log/apache2 \
  apache-reverse-proxy
```

## Let's Encrypt Zertifikate

### Neues Zertifikat erstellen

1. Stellen Sie sicher, dass Ihre Domain auf den Server zeigt
2. Führen Sie im Container aus:
```bash
docker exec -it apache-reverse-proxy certbot --apache -d example.com -d www.example.com
```

### Automatische Erneuerung

Die Zertifikate werden automatisch alle 12 Stunden überprüft und bei Bedarf erneuert.

### Manualle Erneuerung

```bash
docker exec -it apache-reverse-proxy certbot renew
```

## Portainer Integration

### Stack in Portainer einrichten

1. Gehen Sie in Portainer zu "Stacks" → "Add stack"
2. Wählen Sie "Repository" als Build-Methode
3. Geben Sie die Repository-URL ein
4. Setzen Sie `docker-compose.yml` als Compose-Pfad
5. Konfigurieren Sie ggf. Environment-Variablen
6. Deploy starten

### Environment Variablen

- `TZ`: Zeitzone (Standard: UTC)

## Verzeichnisstruktur

```
.
├── Dockerfile                  # Docker Image Definition
├── docker-compose.yml         # Docker Compose Konfiguration
├── docker-entrypoint.sh       # Startskript
├── README.md                  # Diese Datei
├── config/                    # Apache Konfigurationen (Bind-Mount)
│   ├── sites-available/       # Verfügbare Sites
│   ├── sites-enabled/         # Aktivierte Sites
│   ├── conf-available/        # Verfügbare Configs
│   ├── conf-enabled/          # Aktivierte Configs
│   ├── mods-available/        # Verfügbare Module
│   └── mods-enabled/          # Aktivierte Module
├── logs/                      # Apache Logs
└── webroot/                   # Webroot für Let's Encrypt
```

## Konfigurationsbeispiele

### Einfacher Reverse Proxy

```apache
<VirtualHost *:80>
    ServerName app.example.com
    ProxyPass / http://backend-app:3000/
    ProxyPassReverse / http://backend-app:3000/
</VirtualHost>
```

### SSL mit Let's Encrypt

Siehe `config/sites-available/ssl-reverse-proxy-template.conf` für eine vollständige Vorlage.

### WebSocket Support

```apache
# WebSocket Upgrade
RewriteEngine On
RewriteCond %{HTTP:Upgrade} websocket [NC]
RewriteCond %{HTTP:Connection} upgrade [NC]
RewriteRule ^/?(.*) "ws://backend:8080/$1" [P,L]
```

## Updates

### Image aktualisieren

1. Neues Image bauen:
```bash
docker-compose build --no-cache
```

2. Container neu starten:
```bash
docker-compose down
docker-compose up -d
```

Die Konfigurationen und Zertifikate bleiben durch die Bind-Mounts erhalten.

### Apache/Ubuntu Updates

Das Basis-Image verwendet Ubuntu 22.04 LTS. Für Sicherheitsupdates:

```bash
docker-compose pull
docker-compose up -d
```

## Troubleshooting

### Logs prüfen

```bash
# Container Logs
docker-compose logs -f

# Apache Error Logs
tail -f logs/error.log

# Apache Access Logs
tail -f logs/access.log
```

### Konfiguration testen

```bash
docker exec -it apache-reverse-proxy apache2ctl configtest
```

### Let's Encrypt Probleme

1. Prüfen Sie, ob Port 80 erreichbar ist
2. Stellen Sie sicher, dass die Domain korrekt aufgelöst wird
3. Überprüfen Sie die Logs:
```bash
docker exec -it apache-reverse-proxy tail -f /var/log/letsencrypt/letsencrypt.log
```

## Sicherheitshinweise

- Halten Sie das Image regelmäßig aktuell
- Verwenden Sie starke SSL-Konfigurationen (siehe Templates)
- Beschränken Sie den Zugriff auf die Konfigurationsdateien
- Aktivieren Sie Security Headers (in den Templates enthalten)
- Überwachen Sie die Logs auf verdächtige Aktivitäten

## Support

Bei Problemen:
1. Prüfen Sie die Logs
2. Testen Sie die Apache-Konfiguration
3. Stellen Sie sicher, dass alle Ports frei sind
4. Überprüfen Sie die DNS-Einstellungen für Let's Encrypt