# buzz-sprig-tailscale

[`block/buzz-sprig`](https://github.com/block/buzz) on [`graphyte-labs/tailscale`](https://github.com/graphyte-labs/tailscale), so a Buzz agent can reach a tailnet-only relay and AI gateway from a userspace container (e.g. Railway). Rebuilt when either upstream moves.

```
ghcr.io/graphyte-labs/buzz-sprig-tailscale:<sprig>   # e.g. sha-8af2d91
ghcr.io/graphyte-labs/buzz-sprig-tailscale:latest
```

Tags follow Block's sprig commit. The image is rebuilt in place when a new Tailscale release lands, so pin by digest if you need it fixed.

## How it works

1. Joins the tailnet with `containerboot` as user `agent`, in userspace mode. If tailscaled stops, the container exits.
2. Resolves the host in `BUZZ_RELAY_URL` to its Service IP through tailscaled, points that host at `127.0.0.1` in `/etc/hosts`, and runs `socat` on localhost:443 piping to `tailscale nc <Service IP> 443`. The agent keeps the original hostname for TLS and signed authentication.
3. Exports `HTTPS_PROXY` and `HTTP_PROXY` (tailscaled's outbound proxy) for everything else, e.g. the AI gateway. The relay host goes in `NO_PROXY`, so Buzz's REST calls use the same tunnel as its WebSocket.
4. Unsets `TS_AUTHKEY` and runs `buzz-acp` as `agent`. Root only prepares `TS_STATE_DIR` (volumes are mounted root-owned), writes `/etc/hosts` and binds port 443.

## Why the relay workaround

`buzz-acp` opens its relay WebSocket directly and ignores `HTTPS_PROXY`. In userspace mode only tailscaled can reach the tailnet, and the relay must be reached by its own hostname on port 443, since it picks the community from the host and checks it against the TLS certificate and the signed auth URL.

The tunnel dials the Service IP, not the hostname: for names, tailscaled falls back to the container's `/etc/hosts`, which resolves the relay to `127.0.0.1` and loops the tunnel back into itself.

Alternatives considered: kernel-mode Tailscale (needs `NET_ADMIN` and a TUN device), `proxychains` (sprig is a static binary), and polling with `buzz-cli`, whose REST calls do use the proxy but lose push delivery and the harness. Once `buzz-acp` honours the proxy for its WebSocket, step 2 and the root step go away.

## Configuration

| Variable | Purpose |
|---|---|
| `TS_*` | Tailscale, as upstream (`TS_AUTHKEY`, `TS_HOSTNAME`, …). Use an ephemeral key, or `TS_STATE_DIR` on a volume with `TS_AUTH_ONCE=true`. `TS_USERSPACE` is always on. |
| `NO_PROXY` | Hosts that bypass the proxy. Default `localhost,127.0.0.0/8`. |
| `BUZZ_*`, `OPENAI_COMPAT_*` | Agent, as upstream. `BUZZ_RELAY_URL` must be a tailnet host on port 443. `buzz-acp` defaults to `goose`, which is not installed: set `BUZZ_ACP_AGENT_COMMAND=buzz-agent`, and `BUZZ_ACP_MCP_COMMAND=buzz-dev-mcp` to give it tools. |
