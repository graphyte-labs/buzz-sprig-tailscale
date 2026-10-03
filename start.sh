#!/bin/sh
# Joins the tailnet with containerboot, forwards the relay host to localhost:443,
# then runs buzz-acp. Root only writes /etc/hosts and binds :443.
set -eu

export TS_USERSPACE=true \
  TS_SOCKET="${TS_SOCKET:-/tmp/tailscaled.sock}" \
  TS_OUTBOUND_HTTP_PROXY_LISTEN="${TS_OUTBOUND_HTTP_PROXY_LISTEN:-127.0.0.1:1055}"
ts="tailscale --socket=$TS_SOCKET"

# containerboot exits when tailscaled stops running; take the container with it.
(su-exec agent containerboot; kill -TERM 1) &
until su-exec agent $ts status >/dev/null 2>&1; do
  kill -0 "$!" 2>/dev/null || exit 1
  sleep 1
done

# Workaround: buzz-acp's relay WebSocket ignores proxies, and the relay only
# accepts its own hostname on 443 (community lookup, TLS, signed auth URL). So
# point that hostname at localhost:443 and pipe it through the tailnet with
# `tailscale nc`. Remove once buzz-acp honours HTTPS_PROXY for the WebSocket.
relay="${BUZZ_RELAY_URL:-}"; relay="${relay#*://}"; relay="${relay%%[:/]*}"
if [ -n "$relay" ]; then
  echo "127.0.0.1 $relay" >>/etc/hosts
  socat TCP-LISTEN:443,bind=127.0.0.1,reuseaddr,fork,su=agent EXEC:"$ts nc $relay 443" &
fi

proxy="http://$TS_OUTBOUND_HTTP_PROXY_LISTEN"
no_proxy="${NO_PROXY:-localhost,127.0.0.0/8}"
export HTTPS_PROXY="$proxy" HTTP_PROXY="$proxy" NO_PROXY="$no_proxy" \
  https_proxy="$proxy" http_proxy="$proxy" no_proxy="$no_proxy"
exec su-exec agent buzz-acp "$@"
