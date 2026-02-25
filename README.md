# Apache2 Reverse Proxy mit Let's Encrypt

Dieses Docker-Image bietet einen Apache2 Reverse Proxy basierend auf Ubuntu 24.04 LTS mit integrierter Let's Encrypt Unterstützung.

## Features

- **Minimales Ubuntu 24.04 LTS** als Basis
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
├── dyndns-config/             # DynDNS Konfiguration (Bind-Mount)
│   └── config.env.example     # Beispiel-Konfiguration
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

## DynDNS Aktualisierung (IPv4/IPv6)

Dieses Image kann Ihre externe IPv4/IPv6 an einen DynDNS-Dienst melden. Dafür wird eine Konfigurationsdatei via Bind-Mount eingebunden und ein Cronjob alle 5 Minuten (Standard) ausgeführt.

### 1) Konfigurationsverzeichnis erstellen

```bash
mkdir -p dyndns-config
cp dyndns-config/config.env.example dyndns-config/config.env
```

### 2) `docker-compose.yml` Bind-Mount (bereits enthalten)

In der Compose-Datei wird `./dyndns-config` nach `/etc/dyndns` gemountet.

### 3) Konfiguration anpassen (`dyndns-config/config.env`)

Wählen Sie einen Provider und tragen Sie die Zugangsdaten ein. Unterstützt werden aktuell `duckdns`, `cloudflare` und `custom`.

Minimalbeispiele:

- DuckDNS:
```bash
PROVIDER=duckdns
DUCKDNS_TOKEN=your-token
DUCKDNS_DOMAINS=meinhost,meinhost2
```

- Cloudflare (A/AAAA Records per Name):
```bash
PROVIDER=cloudflare
CLOUDFLARE_API_TOKEN=cf_api_token
CLOUDFLARE_ZONE_ID=cf_zone_id
CLOUDFLARE_RECORDS=example.com:A, www.example.com:AAAA
# Optional
CLOUDFLARE_PROXIED=false
CLOUDFLARE_TTL=120
```

- Custom (eine einzige URL mit Platzhaltern `{DOMAIN}`, `{PASSWORT}`, `{IPV4}`, `{IPV6}`):
```bash
PROVIDER=custom
# Die URL darf Kommata enthalten
CUSTOM_URL=https://dyn.example.com/update?d={DOMAIN},ip4={IPV4},ip6={IPV6},pw={PASSWORT}

# Zu aktualisierende Domains (kommagetrennt)
CUSTOM_DOMAINS=app.example.com, www.example.com

# Passwort für den Dienst
CUSTOM_PASSWORT=mein-super-passwort

# Optional
CUSTOM_METHOD=GET
```

Optionale Einstellungen für IP-Ermittlung und Zeitplan:

```bash
# Falls Sie keine IPv6 pflegen möchten
DISABLE_IPV6=false

# Cron-Zeitplan für Updates (Standard: */5 * * * *)
DYNDNS_CRON=*/5 * * * *
```

### 4) Starten/Neu starten

```bash
docker-compose up -d --build
```

Das initiale Update wird beim Containerstart ausgeführt. Laufende Updates erfolgen gemäß Cronplan. Log-Ausgaben (Erfolg und Fehler) sind direkt in den Docker-Logs sichtbar (`docker logs apache-reverse-proxy`).

## IPv6 Konfiguration

Standardmäßig hat ein Docker-Container auf einem Bridge-Netzwerk keine IPv6-Konnektivität. Damit der Container seine externe IPv6-Adresse ermitteln und per DynDNS melden kann, muss IPv6 im Docker-Netzwerk aktiviert werden.

### Variante 1: Bridge-Netzwerk mit IPv6 (empfohlen)

Diese Variante ist bereits in der `docker-compose.yml` vorkonfiguriert. Der Container erhält eine eigene IPv6-Adresse aus dem konfigurierten Subnetz.

#### 1) Docker-Daemon IPv6 aktivieren

Erstellen oder bearbeiten Sie `/etc/docker/daemon.json`:

```json
{
  "ipv6": true,
  "fixed-cidr-v6": "fd00::/80",
  "ip6tables": true,
  "experimental": true
}
```

Danach Docker neu starten:

```bash
sudo systemctl restart docker
```

> **Hinweis:** `ip6tables` und `experimental` aktivieren IPv6-NAT im Docker-Daemon (ab Docker Engine 26.0+). Damit kann der Container über die IPv6 des Hosts nach außen kommunizieren, auch wenn das interne Subnetz eine ULA-Adresse (fd00::) verwendet.

#### 2) IPv6-Subnetz konfigurieren

In `docker-compose.yml` ist das IPv6-Subnetz über die Umgebungsvariable `IPV6_SUBNET` konfigurierbar (Standard: `fd00:dead:beef::/48`).

Für **native, global-routbare IPv6** (Container erhält eine öffentliche IPv6):

```bash
# Beispiel: Ihr Host hat das Subnetz 2001:db8:1::/48
# Weisen Sie dem Docker-Netzwerk ein Teilsubnetz zu:
IPV6_SUBNET=2001:db8:1:1::/80 docker compose up -d
```

Oder setzen Sie die Variable in einer `.env`-Datei:

```bash
IPV6_SUBNET=2001:db8:1:1::/80
```

> **Hinweis:** Wenn Sie ein öffentliches IPv6-Subnetz verwenden, muss der Host das Routing für dieses Subnetz an die Docker-Bridge weiterleiten (z. B. über NDP-Proxy oder statische Routen).

#### 3) Prüfen, ob IPv6 funktioniert

```bash
# IPv6-Adresse des Containers anzeigen
docker exec apache-reverse-proxy ip -6 addr show

# IPv6-Konnektivität testen
docker exec apache-reverse-proxy curl -6 -s https://api6.ipify.org

# DynDNS-Update manuell auslösen
docker exec apache-reverse-proxy /usr/local/bin/dyndns-updater.sh
```

### Variante 2: Host-Netzwerk (einfachste Methode)

Wenn der Container den Netzwerk-Stack des Hosts direkt verwenden soll, nutzen Sie die mitgelieferte alternative Compose-Datei:

```bash
docker compose -f docker-compose.host-network.yml up -d
```

**Vorteile:**
- IPv6 funktioniert sofort ohne zusätzliche Docker-Konfiguration
- Container nutzt die globale IPv6-Adresse des Hosts

**Nachteile:**
- Keine Netzwerkisolierung (Container teilt alle Host-Ports)
- Port-Mapping (`ports:`) wird ignoriert
- Container-übergreifende DNS-Auflösung über Docker-Netzwerke nicht verfügbar

### IPv6 Troubleshooting

| Problem | Lösung |
|---------|--------|
| `curl -6` schlägt fehl | Docker-Daemon IPv6 prüfen: `docker network inspect proxy-network` → IPv6-Subnetz vorhanden? |
| Keine globale IPv6 im Container | Öffentliches Subnetz statt ULA konfigurieren oder Host-Netzwerk verwenden |
| IPv6 extern nicht erreichbar | NDP-Proxy oder statisches Routing auf dem Host einrichten |
| `DISABLE_IPV6=false` aber kein Update | Log prüfen: `docker logs apache-reverse-proxy \| grep IPv6` |

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

Das Basis-Image verwendet Ubuntu 24.04 LTS. Für Sicherheitsupdates:

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