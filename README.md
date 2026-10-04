# buzz-sprig-tailscale

[`block/buzz-sprig`](https://github.com/block/buzz) on [`graphyte-labs/tailscale`](https://github.com/graphyte-labs/tailscale), so a Buzz agent can reach a tailnet-only relay and AI gateway from a userspace container (e.g. Railway). Rebuilt when either upstream moves.

```
ghcr.io/graphyte-labs/buzz-sprig-tailscale:<sprig>   # e.g. sha-8af2d91
ghcr.io/graphyte-labs/buzz-sprig-tailscale:latest
```

Tags follow Block's sprig commit. The image is rebuilt in place when a new Tailscale release lands, so pin by digest if you need it fixed.

## How it works

1. Joins the tailnet with `containerboot` as user `agent`, in userspace mode. If tailscaled stops, the container exits.
2. Points the host in `BUZZ_RELAY_URL` at `localhost:443`, tunnelled with `tailscale nc`. The relay WebSocket ignores proxies, so this is how it reaches the relay.
3. Exports `HTTPS_PROXY` and `HTTP_PROXY` (tailscaled's outbound proxy) for everything else, e.g. the AI gateway.
4. Runs `buzz-acp` as `agent`. Root is only used to write `/etc/hosts`, bind port 443, and hand `TS_STATE_DIR` to `agent` (volumes are mounted root-owned).

## Why the relay workaround

Step 2 exists because `buzz-acp` opens its relay WebSocket directly and ignores `HTTPS_PROXY`. In userspace mode only tailscaled can reach the tailnet, and the relay must be reached by its own hostname on port 443, since it picks the community from the host and checks it against the TLS certificate and the signed auth URL.

Alternatives considered: kernel-mode Tailscale (needs `NET_ADMIN` and a TUN device), `proxychains` (sprig is a static binary), and polling with `buzz-cli`, whose REST calls do use the proxy but lose push delivery and the harness. Once `buzz-acp` honours the proxy for its WebSocket, step 2 and the root step go away.

## Configuration

| Variable | Purpose |
|---|---|
| `TS_*` | Tailscale, as upstream (`TS_AUTHKEY`, `TS_HOSTNAME`, …). Use an ephemeral key, or `TS_STATE_DIR` on a volume with `TS_AUTH_ONCE=true`. `TS_USERSPACE` is always on. |
| `NO_PROXY` | Hosts that bypass the proxy. Default `localhost,127.0.0.0/8`. |
| `BUZZ_*`, `OPENAI_COMPAT_*` | Agent, as upstream. `BUZZ_RELAY_URL` must be a tailnet host on port 443. `buzz-acp` defaults to `goose`, which is not installed: set `BUZZ_ACP_AGENT_COMMAND=buzz-agent`, and `BUZZ_ACP_MCP_COMMAND=buzz-dev-mcp` to give it tools. |
