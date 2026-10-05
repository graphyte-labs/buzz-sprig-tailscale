#!/bin/sh
# Joins the tailnet with containerboot, forwards the relay host to localhost:443,
# then runs buzz-acp. Root prepares TS_STATE_DIR, writes /etc/hosts and binds :443.
set -eu

export TS_USERSPACE=true \
  TS_SOCKET="${TS_SOCKET:-/tmp/tailscaled.sock}" \
  TS_OUTBOUND_HTTP_PROXY_LISTEN="${TS_OUTBOUND_HTTP_PROXY_LISTEN:-127.0.0.1:1055}"
ts="tailscale --socket=$TS_SOCKET"

# Volumes are mounted root-owned, but tailscaled runs as agent.
if [ -n "${TS_STATE_DIR:-}" ]; then
  install -d -o agent -g agent "$TS_STATE_DIR"
  chown agent:agent "$TS_STATE_DIR"
fi

# containerboot exits when tailscaled stops running; take the container with it.
(su-exec agent containerboot; kill -TERM 1) &
until su-exec agent $ts status >/dev/null 2>&1; do
  kill -0 "$!" 2>/dev/null || exit 1
  sleep 1
done

# Workaround: buzz-acp's relay WebSocket ignores proxies, and the relay only
# accepts its own hostname on 443 (community lookup, TLS, signed auth URL). So
# point that hostname at localhost:443 and pipe it to the relay's Service IP with
# `tailscale nc`. Dial the IP, not the name: tailscaled falls back to /etc/hosts
# for names, which would send the tunnel back into itself.
# Only wss:// on the default port is tunnelled.
url="${BUZZ_RELAY_URL:-}"
case "$url" in
  '' | wss://*) relay="${url#wss://}"; relay="${relay%%/*}" ;;
  *) relay=: ;;
esac
case "$relay" in *:*)
  printf 'BUZZ_RELAY_URL must be wss://host[/path] on port 443: %s\n' "$url" >&2; exit 1 ;;
esac
if [ -n "$relay" ]; then
  vip="$(su-exec agent $ts dns query --json "$relay" A | jq -er 'select(.ResponseCode == "RCodeSuccess") | [.Answers[]? | select(.Type == "TypeA") | .Body] | .[0] // empty')" || {
    printf 'failed to resolve Buzz relay Service IP: %s\n' "$relay" >&2
    exit 1
  }
  grep -qxF "127.0.0.1 $relay" /etc/hosts || echo "127.0.0.1 $relay" >>/etc/hosts
  socat TCP-LISTEN:443,bind=127.0.0.1,reuseaddr,fork,su=agent EXEC:"$ts nc $vip 443" &
fi

# The relay goes direct (NO_PROXY), so its REST calls use the same tunnel.
proxy="http://$TS_OUTBOUND_HTTP_PROXY_LISTEN"
no_proxy="localhost,127.0.0.0/8,::1${NO_PROXY:+,$NO_PROXY}${relay:+,$relay}"
export HTTPS_PROXY="$proxy" HTTP_PROXY="$proxy" NO_PROXY="$no_proxy" \
  https_proxy="$proxy" http_proxy="$proxy" no_proxy="$no_proxy"

# Only needed for the first login; keep it away from the agent's shell.
unset TS_AUTHKEY TS_AUTH_KEY
exec su-exec agent buzz-acp "$@"
