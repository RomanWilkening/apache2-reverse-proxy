#!/bin/bash
set -euo pipefail

# DynDNS Updater (Custom-only)

CONFIG_FILE="/etc/dyndns/config.env"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

if [ ! -f "$CONFIG_FILE" ]; then
    log "Kein DynDNS-Config gefunden unter $CONFIG_FILE. Beende."
    exit 0
fi

# Load configuration (supports simple KEY=VALUE lines)
# shellcheck disable=SC2046
set -a
. "$CONFIG_FILE"
set +a

DISABLE_IPV4="${DISABLE_IPV4:-false}"
DISABLE_IPV6="${DISABLE_IPV6:-false}"

discover_ipv4() {
    [ "$DISABLE_IPV4" = "true" ] && return 0
    local endpoints=(
        "https://api.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://ifconfig.co/ip"
    )
    local ip
    for url in "${endpoints[@]}"; do
        ip=$(curl -4 -fsS "$url" | tr -d '\n\r' || true)
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
        "https://ifconfig.co/ip"
    )
    local ip
    for url in "${endpoints[@]}"; do
        ip=$(curl -6 -fsS "$url" | tr -d '\n\r' || true)
        if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]]; then
            IPV6="$ip"
            return 0
        fi
    done
    return 1
}

IPV4=""; IPV6=""
discover_ipv4 || log "Warnung: Konnte externe IPv4 nicht ermitteln."
discover_ipv6 || log "Warnung: Konnte externe IPv6 nicht ermitteln."

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
            else
                log "Custom: Kein A-Update nötig für ${domain} (bestehendes A == $IPV4)."
            fi
        fi

        if [ "$DISABLE_IPV6" != "true" ] && [ -n "$IPV6" ]; then
            checked_any=true
            local current_aaaa
            current_aaaa=$(resolve_aaaa_records "$domain" || true)
            if ! echo "$current_aaaa" | grep -qx "$IPV6" 2>/dev/null; then
                do_update=true
            else
                log "Custom: Kein AAAA-Update nötig für ${domain} (bestehendes AAAA == $IPV6)."
            fi
        fi

        if [ "$checked_any" = false ]; then
            log "Custom: Keine öffentliche IP ermittelt oder Updates deaktiviert. Überspringe ${domain}."
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

            local resp
            if [ "$method" = "POST" ]; then
                resp=$(curl -fsS -X POST "$url" || true)
            else
                resp=$(curl -fsS "$url" || true)
            fi
            log "Custom: Update ausgeführt für ${domain}. Antwort: ${resp}"
            [ -z "$resp" ] && overall_rc=1
        else
            log "Custom: Überspringe Update für ${domain} (keine Änderung erkannt)."
        fi
    done

    return $overall_rc
}

update_custom

