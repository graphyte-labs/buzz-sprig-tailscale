# syntax=docker/dockerfile:1
# Block's buzz-sprig agent runtime on our tailscale image, so the agent can reach
# a tailnet-only Buzz relay and AI gateway from a userspace container.
# Versions come from the build workflow; there are deliberately no defaults.
ARG SPRIG_VERSION
ARG TAILSCALE_VERSION
FROM ghcr.io/block/buzz-sprig:${SPRIG_VERSION} AS sprig

FROM ghcr.io/graphyte-labs/tailscale:${TAILSCALE_VERSION}

# bash: buzz-dev-mcp shell; git, curl: agent tooling; socat, su-exec: start.sh.
RUN apk add --no-cache bash curl git socat su-exec \
    && adduser -D -h /home/agent agent

COPY --link --from=sprig /usr/local/bin/ /usr/local/bin/
COPY --link --chmod=0755 start.sh /usr/local/bin/buzz-sprig-start

ENV HOME=/home/agent
WORKDIR /home/agent

# ENTRYPOINT (JSON logs) is inherited from the tailscale image.
CMD ["/usr/local/bin/buzz-sprig-start"]
