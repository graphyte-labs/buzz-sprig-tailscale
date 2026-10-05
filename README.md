# buzz-sprig-tailscale

Block's [`buzz-sprig`](https://github.com/block/buzz) and [Goose](https://github.com/aaif-goose/goose) on [`graphyte-labs/tailscale`](https://github.com/graphyte-labs/tailscale), for running a Buzz agent in a userspace container (e.g. Railway) when the Buzz relay and the AI gateway are only reachable over the tailnet.

```
ghcr.io/graphyte-labs/buzz-sprig-tailscale:<sprig>   # e.g. sha-8af2d91
ghcr.io/graphyte-labs/buzz-sprig-tailscale:latest
```

Contains `buzz-acp`, `buzz-agent`, `buzz-dev-mcp` and `buzz` from sprig, plus `goose`. The tag is Block's sprig commit and `latest` follows Block's `main`. A tag is rebuilt in place when our Tailscale image or Goose has a new release (labels `org.opencontainers.image.base.name` and `io.github.aaif-goose.version`), so pin by digest. Goose downloads are checked against their GitHub build attestation.

## Running with Goose

```sh
docker run -d -v agent:/data \
  -e TS_AUTHKEY=tskey-auth-… -e TS_HOSTNAME=my-agent \
  -e TS_STATE_DIR=/data/tailscale -e TS_AUTH_ONCE=true \
  -e BUZZ_PRIVATE_KEY=… -e BUZZ_RELAY_URL=wss://relay.example.ts.net \
  -e GOOSE_PATH_ROOT=/data/goose \
  -e OPENAI_HOST=https://gateway.example.ts.net -e OPENAI_API_KEY=… \
  ghcr.io/graphyte-labs/buzz-sprig-tailscale@sha256:…
```

Goose is `buzz-acp`'s default agent. It reads `$GOOSE_PATH_ROOT/config/config.yaml`. List every extension there, `buzz-dev-mcp` included, and leave `BUZZ_ACP_MCP_COMMAND` unset: Goose drops its configured extensions when the harness passes any ([goose#11643](https://github.com/aaif-goose/goose/issues/11643)).

```yaml
GOOSE_PROVIDER: openai
GOOSE_MODEL: <model>
GOOSE_MODE: auto              # no one is there to approve tool calls
GOOSE_DISABLE_KEYRING: true   # no system keyring in the container
extensions:
  buzz:
    name: buzz
    type: stdio
    cmd: buzz-dev-mcp
    args: []
    enabled: true
  gateway:
    name: gateway
    type: streamable_http
    uri: https://gateway.example.ts.net/mcp
    enabled: true
```

To run `buzz-agent` instead, set `BUZZ_ACP_AGENT_COMMAND=buzz-agent` and `BUZZ_ACP_MCP_COMMAND=buzz-dev-mcp`. `buzz-acp` gives it a single stdio MCP server and no HTTP ones.

## How it works

1. Joins the tailnet with `containerboot` in userspace mode, as user `tsd`. The agent runs as `agent`, so it cannot read the node's state or auth key, or change the node through tailscaled's socket. If tailscaled stops, the container exits.
2. Tunnels the relay. `buzz-acp`'s WebSocket ignores `HTTPS_PROXY`, and the relay only accepts its own hostname on port 443 (TLS and signed auth). So the host in `BUZZ_RELAY_URL` points to `127.0.0.1` in `/etc/hosts`, and `socat` on port 443 pipes to `tailscale nc <Service IP> 443`. The tunnel dials the IP: given the name, tailscaled would resolve it through `/etc/hosts` and loop back into itself.
3. Exports `HTTPS_PROXY` and `HTTP_PROXY` (tailscaled's outbound proxy) for everything else, such as model and MCP calls. The relay host is added to `NO_PROXY`, so Buzz's REST calls use the tunnel too.
4. Runs `buzz-acp` as `agent` under `tini`, which reaps processes the agent's shell leaves behind. Root only prepares `TS_STATE_DIR`, writes `/etc/hosts` and binds port 443.

## Configuration

| Variable | Purpose |
|---|---|
| `TS_*` | Tailscale, as upstream. `TS_USERSPACE` is always on. For a stable node, use `TS_STATE_DIR` on a volume with `TS_AUTH_ONCE=true`; otherwise an ephemeral key. `TS_STATE_DIR` is handed to `tsd` entirely, so give it its own directory, not the volume root the agent writes to. |
| `BUZZ_*` | Buzz, as upstream. `BUZZ_RELAY_URL` must be `wss://` to a tailnet host on port 443. |
| `GOOSE_*`, `OPENAI_*` | Goose, as upstream. |
| `OPENAI_COMPAT_*` | `buzz-agent` only. |
| `TZ` | Timezone, e.g. `Europe/Tallinn`. Goose's scheduler reads cron times in it. Default UTC. |
| `NO_PROXY` | Extra hosts that bypass the proxy. Localhost always does. |
