#!/bin/bash
set -euo pipefail

# DynDNS Updater
# Supported providers: duckdns, cloudflare, custom

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

PROVIDER="${PROVIDER:-}"
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

update_duckdns() {
    # Required: DUCKDNS_TOKEN, DUCKDNS_DOMAINS (comma-separated without spaces)
    if [ -z "${DUCKDNS_TOKEN:-}" ] || [ -z "${DUCKDNS_DOMAINS:-}" ]; then
        log "DuckDNS: DUCKDNS_TOKEN oder DUCKDNS_DOMAINS fehlt."
        return 1
    fi
    local url="https://www.duckdns.org/update?domains=${DUCKDNS_DOMAINS}&token=${DUCKDNS_TOKEN}"
    if [ -n "$IPV4" ]; then
        url+="&ip=$IPV4"
    else
        url+="&clear=true" # clears IPv4
    fi
    if [ -n "$IPV6" ]; then
        url+="&ipv6=$IPV6"
    fi
    local resp
    resp=$(curl -fsS "$url" || true)
    if echo "$resp" | grep -qi "OK"; then
        log "DuckDNS: Update erfolgreich für ${DUCKDNS_DOMAINS}."
    else
        log "DuckDNS: Update fehlgeschlagen: $resp"
        return 1
    fi
}

cloudflare_api() {
    local method="$1"; shift
    local path="$1"; shift
    local data="${1:-}"
    if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
        log "Cloudflare: CLOUDFLARE_API_TOKEN fehlt."
        return 1
    fi
    local curl_args=(
        -fsS -X "$method" "https://api.cloudflare.com/client/v4${path}"
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
        -H "Content-Type: application/json"
    )
    if [ -n "$data" ]; then
        curl_args+=(--data "$data")
    fi
    curl "${curl_args[@]}"
}

update_cloudflare_record() {
    local type="$1"; local name="$2"; local content="$3"
    local proxied="${CLOUDFLARE_PROXIED:-false}"
    local ttl="${CLOUDFLARE_TTL:-120}"
    if [ -z "${CLOUDFLARE_ZONE_ID:-}" ]; then
        log "Cloudflare: CLOUDFLARE_ZONE_ID fehlt."
        return 1
    fi
    # Find record id
    local qpath="/zones/${CLOUDFLARE_ZONE_ID}/dns_records?type=${type}&name=${name}"
    local rec
    rec=$(cloudflare_api GET "$qpath" || true)
    local id
    id=$(echo "$rec" | jq -r '.result[0].id // empty')
    if [ -z "$id" ]; then
        log "Cloudflare: DNS-Record nicht gefunden: ${name} (${type})."
        return 1
    fi
    local payload
    payload=$(jq -cn --arg t "$type" --arg n "$name" --arg c "$content" --argjson p $( [ "$proxied" = "true" ] && echo true || echo false ) --argjson ttl "$ttl" '{type:$t,name:$n,content:$c,proxied:$p,ttl:$ttl}')
    local resp
    resp=$(cloudflare_api PUT "/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${id}" "$payload" || true)
    if echo "$resp" | jq -e '.success == true' >/dev/null 2>&1; then
        log "Cloudflare: ${name} ${type} aktualisiert auf ${content}."
    else
        log "Cloudflare: Update fehlgeschlagen für ${name} ${type}: $(echo "$resp" | jq -r '.errors[0].message // . | @json')"
        return 1
    fi
}

update_cloudflare() {
    # CLOUDFLARE_RECORDS: comma-separated entries like "example.com:A, www.example.com:AAAA"
    if [ -z "${CLOUDFLARE_RECORDS:-}" ]; then
        log "Cloudflare: CLOUDFLARE_RECORDS fehlt."
        return 1
    fi
    local IFS=','
    for entry in $CLOUDFLARE_RECORDS; do
        entry=$(echo "$entry" | xargs)
        local name="${entry%%:*}"
        local type="${entry##*:}"
        case "$type" in
            A)
                if [ -n "$IPV4" ]; then
                    update_cloudflare_record A "$name" "$IPV4" || true
                else
                    log "Cloudflare: Überspringe ${name} A (keine IPv4)."
                fi
                ;;
            AAAA)
                if [ -n "$IPV6" ]; then
                    update_cloudflare_record AAAA "$name" "$IPV6" || true
                else
                    log "Cloudflare: Überspringe ${name} AAAA (keine IPv6)."
                fi
                ;;
            *)
                log "Cloudflare: Unbekannter Typ in CLOUDFLARE_RECORDS: $type"
                ;;
        esac
    done
}

update_custom() {
    # CUSTOM_URL supports placeholders {IPV4} and {IPV6}
    if [ -z "${CUSTOM_URL:-}" ]; then
        log "Custom: CUSTOM_URL fehlt."
        return 1
    fi
    local url="$CUSTOM_URL"
    url=${url//\{IPV4\}/$IPV4}
    url=${url//\{IPV6\}/$IPV6}
    local method="${CUSTOM_METHOD:-GET}"
    local resp
    if [ "$method" = "POST" ]; then
        resp=$(curl -fsS -X POST "$url" || true)
    else
        resp=$(curl -fsS "$url" || true)
    fi
    log "Custom: Antwort: ${resp}"
}

case "$PROVIDER" in
    duckdns)
        update_duckdns ;;
    cloudflare)
        update_cloudflare ;;
    custom)
        update_custom ;;
    "")
        log "Kein PROVIDER definiert. Vorgang abgebrochen."
        exit 0 ;;
    *)
        log "Unbekannter PROVIDER: $PROVIDER" ;;
esac

