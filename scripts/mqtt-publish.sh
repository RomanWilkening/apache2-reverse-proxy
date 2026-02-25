#!/bin/bash
# MQTT Publisher for Home Assistant Integration
# Publishes DynDNS update status via MQTT with HA auto-discovery

set -euo pipefail

CONFIG_FILE="/etc/dyndns/config.env"

# --- Arguments ---
# Usage: mqtt-publish.sh <ipv4> <ipv6> <status> [timestamp]
#   ipv4      : Current public IPv4 (or empty string)
#   ipv6      : Current public IPv6 (or empty string)
#   status    : "OK" or "Fehler"
#   timestamp : ISO 8601 timestamp of last successful update (optional)

IPV4="${1:-}"
IPV6="${2:-}"
STATUS="${3:-}"
LAST_SUCCESS="${4:-}"

log() {
    echo "[MQTT $(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[MQTT $(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

if [ ! -f "$CONFIG_FILE" ]; then
    exit 0
fi

# Load configuration
set -a
. "$CONFIG_FILE"
set +a

MQTT_HOST="${MQTT_HOST:-}"
MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_USER="${MQTT_USER:-}"
MQTT_PASSWORD="${MQTT_PASSWORD:-}"
MQTT_TOPIC_PREFIX="${MQTT_TOPIC_PREFIX:-dyndns}"

if [ -z "$MQTT_HOST" ]; then
    exit 0
fi

if ! command -v mosquitto_pub >/dev/null 2>&1; then
    log_error "mosquitto_pub nicht gefunden. Paket mosquitto-clients installieren."
    exit 1
fi

# Build common mosquitto_pub options
MQTT_OPTS=(-h "$MQTT_HOST" -p "$MQTT_PORT")
if [ -n "$MQTT_USER" ]; then
    MQTT_OPTS+=(-u "$MQTT_USER")
    if [ -n "$MQTT_PASSWORD" ]; then
        MQTT_OPTS+=(-P "$MQTT_PASSWORD")
    fi
fi

DEVICE_ID="dyndns_updater"
STATE_TOPIC="${MQTT_TOPIC_PREFIX}/state"
AVAIL_TOPIC="${MQTT_TOPIC_PREFIX}/status"

# State file to track whether discovery has been sent
DISCOVERY_SENT_FLAG="/tmp/.mqtt_discovery_sent"

send_discovery() {
    log "Sende Home Assistant MQTT Auto-Discovery..."

    local device_json
    device_json=$(cat <<EOJSON
"dev":{"ids":["${DEVICE_ID}"],"name":"DynDNS Updater","mf":"apache2-reverse-proxy","mdl":"DynDNS"}
EOJSON
    )
    local avail_json="\"avty_t\":\"${AVAIL_TOPIC}\",\"pl_avail\":\"online\",\"pl_not_avail\":\"offline\""

    # Sensor: IPv4
    mosquitto_pub "${MQTT_OPTS[@]}" -r -t "homeassistant/sensor/${DEVICE_ID}_ipv4/config" -m \
        "{\"name\":\"IPv4 Adresse\",\"uniq_id\":\"${DEVICE_ID}_ipv4\",\"stat_t\":\"${STATE_TOPIC}\",\"val_tpl\":\"{{ value_json.ipv4 }}\",\"icon\":\"mdi:ip-network\",${device_json},${avail_json}}" || true

    # Sensor: IPv6
    mosquitto_pub "${MQTT_OPTS[@]}" -r -t "homeassistant/sensor/${DEVICE_ID}_ipv6/config" -m \
        "{\"name\":\"IPv6 Adresse\",\"uniq_id\":\"${DEVICE_ID}_ipv6\",\"stat_t\":\"${STATE_TOPIC}\",\"val_tpl\":\"{{ value_json.ipv6 }}\",\"icon\":\"mdi:ip-network\",${device_json},${avail_json}}" || true

    # Sensor: Status
    mosquitto_pub "${MQTT_OPTS[@]}" -r -t "homeassistant/sensor/${DEVICE_ID}_status/config" -m \
        "{\"name\":\"Update Status\",\"uniq_id\":\"${DEVICE_ID}_status\",\"stat_t\":\"${STATE_TOPIC}\",\"val_tpl\":\"{{ value_json.status }}\",\"icon\":\"mdi:cloud-check\",${device_json},${avail_json}}" || true

    # Sensor: Last successful update
    mosquitto_pub "${MQTT_OPTS[@]}" -r -t "homeassistant/sensor/${DEVICE_ID}_last_success/config" -m \
        "{\"name\":\"Letzte erfolgreiche Aktualisierung\",\"uniq_id\":\"${DEVICE_ID}_last_success\",\"stat_t\":\"${STATE_TOPIC}\",\"val_tpl\":\"{{ value_json.last_success }}\",\"icon\":\"mdi:clock-check-outline\",\"dev_cla\":\"timestamp\",${device_json},${avail_json}}" || true

    log "Home Assistant MQTT Auto-Discovery gesendet."
}

# Send discovery once per container lifetime
if [ ! -f "$DISCOVERY_SENT_FLAG" ]; then
    if send_discovery; then
        touch "$DISCOVERY_SENT_FLAG"
    fi
fi

# Publish availability
mosquitto_pub "${MQTT_OPTS[@]}" -r -t "$AVAIL_TOPIC" -m "online" || true

# Read persisted last_success if not provided
LAST_SUCCESS_FILE="/tmp/.mqtt_last_success"
if [ -z "$LAST_SUCCESS" ] && [ -f "$LAST_SUCCESS_FILE" ]; then
    LAST_SUCCESS=$(cat "$LAST_SUCCESS_FILE")
fi

# Build and publish state JSON
STATE_JSON=$(printf '{"ipv4":"%s","ipv6":"%s","status":"%s","last_success":"%s"}' \
    "$IPV4" "$IPV6" "$STATUS" "$LAST_SUCCESS")

if mosquitto_pub "${MQTT_OPTS[@]}" -r -t "$STATE_TOPIC" -m "$STATE_JSON"; then
    log "MQTT State publiziert: ${STATE_JSON}"
else
    log_error "MQTT State konnte nicht publiziert werden."
fi

# Persist last_success timestamp
if [ "$STATUS" = "OK" ] && [ -n "$LAST_SUCCESS" ]; then
    echo "$LAST_SUCCESS" > "$LAST_SUCCESS_FILE"
fi
