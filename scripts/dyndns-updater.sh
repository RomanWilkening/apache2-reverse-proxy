#!/bin/bash
set -euo pipefail

# DynDNS Updater (Custom-only)

CONFIG_FILE="/etc/dyndns/config.env"

# Log to Docker stdout so messages appear in 'docker logs'
# NOTE: Cron already redirects stdout/stderr to /proc/1/fd/{1,2},
# so we only write there when NOT already redirected (e.g. manual run).
log() {
    local msg="[DynDNS $(date +'%Y-%m-%d %H:%M:%S')] $*"
    if [ -w /proc/1/fd/1 ] && ! [ /proc/1/fd/1 -ef /dev/stdout ] 2>/dev/null; then
        echo "$msg" > /proc/1/fd/1
    else
        echo "$msg"
    fi
}

log_error() {
    local msg="[DynDNS $(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*"
    if [ -w /proc/1/fd/2 ] && ! [ /proc/1/fd/2 -ef /dev/stderr ] 2>/dev/null; then
        echo "$msg" > /proc/1/fd/2
    else
        echo "$msg" >&2
    fi
}

if [ ! -f "$CONFIG_FILE" ]; then
    log "Kein DynDNS-Config gefunden unter $CONFIG_FILE. Beende."
    exit 0
fi

# Load configuration (supports simple KEY=VALUE lines, even unquoted values with spaces)
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    # Only process lines that look like KEY=VALUE
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z_0-9]*)=(.*) ]]; then
        key="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        # Strip surrounding quotes if present
        if [[ "$val" =~ ^\"(.*)\"$ ]] || [[ "$val" =~ ^\'(.*)\'$ ]]; then
            val="${BASH_REMATCH[1]}"
        fi
        export "$key=$val"
    fi
done < "$CONFIG_FILE"

DISABLE_IPV4="${DISABLE_IPV4:-false}"
DISABLE_IPV6="${DISABLE_IPV6:-false}"
CURL_TIMEOUT="${CURL_TIMEOUT:-10}"

discover_ipv4() {
    [ "$DISABLE_IPV4" = "true" ] && return 0
    local endpoints=(
        "https://api.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://checkip.amazonaws.com"
        "https://ipinfo.io/ip"
        "https://api.seeip.org"
    )
    local ip
    for url in "${endpoints[@]}"; do
        ip=$(curl -4 -fsS --max-time "$CURL_TIMEOUT" "$url" 2>/dev/null | tr -d '\n\r' || true)
        if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            IPV4="$ip"
            return 0
        fi
    done
    return 1
}

discover_ipv6() {
    [ "$DISABLE_IPV6" = "true" ] && return 0
    local endpoints=(
        "https://api6.ipify.org"
        "https://ipv6.icanhazip.com"
        "https://v6.ident.me"
        "https://api64.ipify.org"
    )
    local ip
    for url in "${endpoints[@]}"; do
        ip=$(curl -6 -fsS --max-time "$CURL_TIMEOUT" "$url" 2>/dev/null | tr -d '\n\r' || true)
        if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]]; then
            IPV6="$ip"
            return 0
        fi
    done
    return 1
}

LAST_IP_FILE="/tmp/dyndns_last_ips"
LAST_IPV4=""; LAST_IPV6=""
if [ -f "$LAST_IP_FILE" ]; then
    LAST_IPV4=$(sed -n '1p' "$LAST_IP_FILE")
    LAST_IPV6=$(sed -n '2p' "$LAST_IP_FILE")
fi

IPV4=""; IPV6=""
if discover_ipv4; then
    if [ -n "$IPV4" ] && [ "$IPV4" != "$LAST_IPV4" ]; then
        log "Neue IPv4 ermittelt: $IPV4"
    fi
else
    log_error "Konnte externe IPv4 nicht ermitteln (alle Endpunkte fehlgeschlagen)."
fi
if discover_ipv6; then
    if [ -n "$IPV6" ] && [ "$IPV6" != "$LAST_IPV6" ]; then
        log "Neue IPv6 ermittelt: $IPV6"
    fi
else
    log_error "Konnte externe IPv6 nicht ermitteln (alle Endpunkte fehlgeschlagen)."
fi

# Aktuelle IPs für nächsten Lauf speichern
printf '%s\n%s\n' "$IPV4" "$IPV6" > "$LAST_IP_FILE"

# Wenn sich keine IP geändert hat, gibt es nichts zu tun
if [ "$IPV4" = "$LAST_IPV4" ] && [ "$IPV6" = "$LAST_IPV6" ]; then
    exit 0
fi

urldecode() {
    local data="$1"
    data="${data//+/ }"
    printf '%b' "${data//%/\\x}"
}

extract_host_from_url() {
    # Heuristik: aus Query-Parametern einen Hostnamen lesen
    # Unterstützte Param-Namen: host, hostname, name, domain, record, fqdn
    local url="$1"
    case "$url" in
        *\?*) : ;;
        *) echo ""; return 0 ;;
    esac
    local query
    query="${url#*?}"
    query="${query%%#*}"
    local pair key val
    local IFS='&'
    for pair in $query; do
        key="${pair%%=*}"
        val="${pair#*=}"
        key=$(printf '%s' "$key" | tr 'A-Z' 'a-z')
        val=$(urldecode "$val")
        case "$key" in
            host|hostname|name|domain|record|fqdn)
                echo "$val"
                return 0
                ;;
        esac
    done
    echo ""
}

resolve_a_records() {
    local host="$1"
    getent ahostsv4 "$host" | awk '{print $1}' | sort -u
}

resolve_aaaa_records() {
    local host="$1"
    getent ahostsv6 "$host" | awk '{print $1}' | sort -u
}

    

update_custom() {
    # Erwartet eine einzelne URL-Vorlage (CUSTOM_URL) mit Platzhaltern
    # {DOMAIN}, {PASSWORT}, {IPV4}, {IPV6}
    local template_url="${CUSTOM_URL:-}"
    if [ -z "$template_url" ]; then
        log "Custom: CUSTOM_URL fehlt."
        return 1
    fi

    local domains_raw="${CUSTOM_DOMAINS:-}"
    if [ -z "$domains_raw" ]; then
        log "Custom: CUSTOM_DOMAINS fehlt."
        return 1
    fi

    local method="${CUSTOM_METHOD:-GET}"
    local password="${CUSTOM_PASSWORT:-${CUSTOM_PASSWORD:-}}"

    local overall_rc=0

    # Nur die Domainliste wird an Kommas getrennt. Die URL darf Kommas enthalten.
    local IFS=','
    local -a domain_list
    read -ra domain_list <<< "$domains_raw"

    local domain
    for domain in "${domain_list[@]}"; do
        domain=$(echo "$domain" | xargs)
        [ -z "$domain" ] && continue

        local do_update=false
        local checked_any=false

        if [ "$DISABLE_IPV4" != "true" ] && [ -n "$IPV4" ]; then
            checked_any=true
            local current_a
            current_a=$(resolve_a_records "$domain" || true)
            if ! echo "$current_a" | grep -qx "$IPV4" 2>/dev/null; then
                do_update=true
            fi
        fi

        if [ "$DISABLE_IPV6" != "true" ] && [ -n "$IPV6" ]; then
            checked_any=true
            local current_aaaa
            current_aaaa=$(resolve_aaaa_records "$domain" || true)
            if ! echo "$current_aaaa" | grep -qx "$IPV6" 2>/dev/null; then
                do_update=true
            fi
        fi

        if [ "$checked_any" = false ]; then
            continue
        fi

        if [ "$do_update" = true ]; then
            local url="$template_url"
            # Platzhalter ersetzen (Groß-/Kleinschreibung unterstützen)
            url=${url//\{IPV4\}/$IPV4}
            url=${url//\{ipv4\}/$IPV4}
            url=${url//\{IPV6\}/$IPV6}
            url=${url//\{ipv6\}/$IPV6}
            url=${url//\{DOMAIN\}/$domain}
            url=${url//\{domain\}/$domain}
            url=${url//\{PASSWORT\}/$password}
            url=${url//\{passwort\}/$password}
            url=${url//\{PASSWORD\}/$password}
            url=${url//\{password\}/$password}

            # HTML-Entity &amp; in echtes & umwandeln (häufiger Copy-Paste-Fehler)
            url=${url//&amp;/\&}

            local resp http_code
            if [ "$method" = "POST" ]; then
                http_code=$(curl -sS -o /tmp/dyndns_resp -w '%{http_code}' --max-time "$CURL_TIMEOUT" -X POST "$url" || echo "000")
            else
                http_code=$(curl -sS -o /tmp/dyndns_resp -w '%{http_code}' --max-time "$CURL_TIMEOUT" "$url" || echo "000")
            fi
            resp=$(cat /tmp/dyndns_resp 2>/dev/null || true)
            rm -f /tmp/dyndns_resp

            local sent_ips=""
            [ -n "$IPV4" ] && sent_ips="IPv4=${IPV4}"
            [ -n "$IPV6" ] && sent_ips="${sent_ips:+${sent_ips}, }IPv6=${IPV6}"

            if [ "$http_code" -ge 200 ] 2>/dev/null && [ "$http_code" -lt 300 ] 2>/dev/null && [ -n "$resp" ]; then
                log "Update ERFOLGREICH für ${domain} [${sent_ips}] (HTTP ${http_code}). Antwort: ${resp}"
            else
                log_error "Update FEHLGESCHLAGEN für ${domain} (HTTP ${http_code}). Antwort: ${resp}"
                overall_rc=1
            fi
        fi
    done

    return $overall_rc
}

UPDATE_STATUS="OK"
update_custom || UPDATE_STATUS="Fehler"

# MQTT Publishing (optional – only if MQTT_HOST is configured)
if grep -qE '^MQTT_HOST=' "$CONFIG_FILE" 2>/dev/null; then
    MQTT_TIMESTAMP=""
    if [ "$UPDATE_STATUS" = "OK" ]; then
        MQTT_TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    fi
    /usr/local/bin/mqtt-publish.sh "$IPV4" "$IPV6" "$UPDATE_STATUS" "$MQTT_TIMESTAMP" || true
fi

