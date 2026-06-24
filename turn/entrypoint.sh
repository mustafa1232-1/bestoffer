#!/bin/sh
set -eu

TURN_PORT="${TURN_PORT:-3478}"
TURN_MIN_PORT="${TURN_MIN_PORT:-49160}"
TURN_MAX_PORT="${TURN_MAX_PORT:-49200}"
TURN_REALM="${TURN_REALM:-maslaki.local}"
TURN_AUTH_SECRET="${TURN_AUTH_SECRET:-}"
TURN_DISABLE_UDP="${TURN_DISABLE_UDP:-false}"
TURN_PUBLIC_IP="${TURN_PUBLIC_IP:-}"
TURN_PUBLIC_HOST="${TURN_PUBLIC_HOST:-}"

if [ -z "$TURN_AUTH_SECRET" ]; then
  echo "TURN_AUTH_SECRET is required" >&2
  exit 1
fi

if [ -z "$TURN_PUBLIC_IP" ] && [ -n "$TURN_PUBLIC_HOST" ]; then
  TURN_PUBLIC_IP="$(getent ahostsv4 "$TURN_PUBLIC_HOST" | awk 'NR==1{print $1}')"
fi

cat >/etc/turnserver.conf <<EOF
listening-port=$TURN_PORT
listening-ip=0.0.0.0
fingerprint
lt-cred-mech
use-auth-secret
static-auth-secret=$TURN_AUTH_SECRET
realm=$TURN_REALM
stale-nonce
no-cli
no-multicast-peers
min-port=$TURN_MIN_PORT
max-port=$TURN_MAX_PORT
simple-log
EOF

if [ -n "$TURN_PUBLIC_IP" ]; then
  echo "external-ip=$TURN_PUBLIC_IP" >>/etc/turnserver.conf
fi

if [ "$TURN_DISABLE_UDP" = "true" ]; then
  echo "no-udp" >>/etc/turnserver.conf
  echo "no-udp-relay" >>/etc/turnserver.conf
fi

echo "[turn] starting coturn on port $TURN_PORT with realm $TURN_REALM"
if [ -n "$TURN_PUBLIC_IP" ]; then
  echo "[turn] external-ip=$TURN_PUBLIC_IP"
fi

exec turnserver -c /etc/turnserver.conf --no-software-attribute
