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
    local overall_rc=0
    local IFS=','
    local -a url_list
    local -a host_list
    read -ra url_list <<< "$urls"
    read -ra host_list <<< "${CUSTOM_HOSTS:-}"
    local i
    for i in "${!url_list[@]}"; do
        local tmpl
        tmpl=$(echo "${url_list[$i]}" | xargs)
        [ -z "$tmpl" ] && continue
        local target_host=""
        if [ ${#host_list[@]} -gt $i ] && [ -n "${host_list[$i]:-}" ]; then
            target_host=$(echo "${host_list[$i]}" | xargs)
        else
            target_host=$(extract_host_from_url "$tmpl")
        fi

        local do_update=false
        local checked_any=false
        if [ "$DISABLE_IPV4" != "true" ] && [ -n "$IPV4" ] && [ -n "$target_host" ]; then
            checked_any=true
            local current_a
            current_a=$(resolve_a_records "$target_host" || true)
            if ! echo "$current_a" | grep -qx "$IPV4" 2>/dev/null; then
                do_update=true
            else
                log "Custom: Kein A-Update nötig für ${target_host} (bestehendes A == $IPV4)."
            fi
        fi
        if [ "$DISABLE_IPV6" != "true" ] && [ -n "$IPV6" ] && [ -n "$target_host" ]; then
            checked_any=true
            local current_aaaa
            current_aaaa=$(resolve_aaaa_records "$target_host" || true)
            if ! echo "$current_aaaa" | grep -qx "$IPV6" 2>/dev/null; then
                do_update=true
            else
                log "Custom: Kein AAAA-Update nötig für ${target_host} (bestehendes AAAA == $IPV6)."
            fi
        fi

        if [ -z "$target_host" ]; then
            log "Custom: Zielhost nicht ermittelbar aus URL. Führe Update vorsorglich aus."
            do_update=true
        elif [ "$checked_any" = false ]; then
            log "Custom: Keine öffentliche IP ermittelt oder Updates deaktiviert. Überspringe ${target_host}."
            continue
        fi

        if [ "$do_update" = true ]; then
            local url="$tmpl"
            url=${url//\{IPV4\}/$IPV4}
            url=${url//\{IPV6\}/$IPV6}
            local resp
            if [ "$method" = "POST" ]; then
                resp=$(curl -fsS -X POST "$url" || true)
            else
                resp=$(curl -fsS "$url" || true)
            fi
            log "Custom: Update ausgeführt für ${target_host:-unbekannt}. Antwort: ${resp}"
            [ -z "$resp" ] && overall_rc=1
        else
            log "Custom: Überspringe Update für ${target_host} (keine Änderung erkannt)."
        fi
    done
    return $overall_rc
}

update_custom

