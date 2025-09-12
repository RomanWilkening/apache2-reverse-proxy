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

    

update_custom() {
    # CUSTOM_URL or CUSTOM_URLS support placeholders {IPV4} and {IPV6}
    local urls="${CUSTOM_URLS:-}"
    if [ -z "$urls" ] && [ -n "${CUSTOM_URL:-}" ]; then
        urls="$CUSTOM_URL"
    fi
    if [ -z "$urls" ]; then
        log "Custom: CUSTOM_URL(S) fehlt."
        return 1
    fi
    local method="${CUSTOM_METHOD:-GET}"
    local IFS=','
    local overall_rc=0
    for raw in $urls; do
        local tmpl
        tmpl=$(echo "$raw" | xargs)
        [ -z "$tmpl" ] && continue
        local url="$tmpl"
        url=${url//\{IPV4\}/$IPV4}
        url=${url//\{IPV6\}/$IPV6}
        local resp
        if [ "$method" = "POST" ]; then
            resp=$(curl -fsS -X POST "$url" || true)
        else
            resp=$(curl -fsS "$url" || true)
        fi
        log "Custom: Antwort für ${tmpl}: ${resp}"
        [ -z "$resp" ] && overall_rc=1
    done
    return $overall_rc
}

update_custom

