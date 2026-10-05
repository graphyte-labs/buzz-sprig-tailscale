# syntax=docker/dockerfile:1
# Block's buzz-sprig agent runtime on our tailscale image, so the agent can reach
# a tailnet-only Buzz relay and AI gateway from a userspace container.
# Versions come from the build workflow; there are deliberately no defaults.
ARG SPRIG_VERSION
ARG TAILSCALE_VERSION
FROM ghcr.io/block/buzz-sprig:${SPRIG_VERSION} AS sprig

FROM ghcr.io/graphyte-labs/tailscale:${TAILSCALE_VERSION}
ARG GOOSE_VERSION
ARG GOOSE_SHA256_X86_64
ARG GOOSE_SHA256_AARCH64
ARG TARGETARCH

# bash: buzz-dev-mcp shell; git, curl: agent tooling; jq, socat, su-exec: start.sh;
# tzdata: TZ, so scheduled jobs run in local time.
RUN apk add --no-cache bash curl git jq socat su-exec tzdata \
    && adduser -D -h /home/agent agent

# Goose, buzz-acp's default agent. Unlike buzz-agent it can use HTTP MCP servers.
# The workflow verifies the release's build attestation and passes the checksums.
RUN case "$TARGETARCH" in \
      amd64) arch=x86_64 sum=$GOOSE_SHA256_X86_64 ;; \
      arm64) arch=aarch64 sum=$GOOSE_SHA256_AARCH64 ;; \
      *) echo "unsupported arch: $TARGETARCH" >&2; exit 1 ;; \
    esac \
    && curl -fsSLo /tmp/goose.tgz "https://github.com/aaif-goose/goose/releases/download/${GOOSE_VERSION}/goose-${arch}-unknown-linux-musl.tar.gz" \
    && echo "$sum  /tmp/goose.tgz" | sha256sum -c - \
    && tar -xzf /tmp/goose.tgz -C /usr/local/bin --no-same-owner ./goose \
    && rm /tmp/goose.tgz \
    && apk add --no-cache --virtual .strip binutils && strip /usr/local/bin/goose && apk del .strip

COPY --link --from=sprig /usr/local/bin/ /usr/local/bin/
COPY --link --chmod=0755 start.sh /usr/local/bin/buzz-sprig-start

# NO_COLOR: keep ANSI codes out of the JSON log lines.
ENV HOME=/home/agent NO_COLOR=1
WORKDIR /home/agent

# ENTRYPOINT (JSON logs) is inherited from the tailscale image.
CMD ["/usr/local/bin/buzz-sprig-start"]
