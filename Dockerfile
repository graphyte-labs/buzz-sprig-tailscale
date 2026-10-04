# syntax=docker/dockerfile:1
# Block's buzz-sprig agent runtime on our tailscale image, so the agent can reach
# a tailnet-only Buzz relay and AI gateway from a userspace container.
# Versions come from the build workflow; there are deliberately no defaults.
ARG SPRIG_VERSION
ARG TAILSCALE_VERSION
ARG GOOSE_VERSION
FROM ghcr.io/block/buzz-sprig:${SPRIG_VERSION} AS sprig

FROM ghcr.io/graphyte-labs/tailscale:${TAILSCALE_VERSION}
ARG GOOSE_VERSION
ARG TARGETARCH

# bash: buzz-dev-mcp shell; git, curl: agent tooling; jq, socat, su-exec: start.sh;
# tzdata: TZ, so scheduled jobs run in local time.
RUN apk add --no-cache bash curl git jq socat su-exec tzdata \
    && adduser -D -h /home/agent agent

# Goose, as an alternative to buzz-agent: it speaks MCP over HTTP, which
# buzz-agent does not. Select it with BUZZ_ACP_AGENT_COMMAND=goose.
RUN case "$TARGETARCH" in amd64) arch=x86_64 ;; arm64) arch=aarch64 ;; *) exit 1 ;; esac \
    && curl -fsSL "https://github.com/aaif-goose/goose/releases/download/${GOOSE_VERSION}/goose-${arch}-unknown-linux-musl.tar.gz" \
      | tar -xz -C /usr/local/bin --no-same-owner ./goose

COPY --link --from=sprig /usr/local/bin/ /usr/local/bin/
COPY --link --chmod=0755 start.sh /usr/local/bin/buzz-sprig-start

ENV HOME=/home/agent
WORKDIR /home/agent

# ENTRYPOINT (JSON logs) is inherited from the tailscale image.
CMD ["/usr/local/bin/buzz-sprig-start"]
