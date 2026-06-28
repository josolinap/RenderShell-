FROM alpine:3.20 AS tailscale-builder
ARG TS_VERSION=1.86.2
RUN apk add --no-cache curl ca-certificates
WORKDIR /tmp
RUN curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_${TS_VERSION}_amd64.tgz" | \
    tar -xz --strip-components=1

# ---------- Runtime stage ----------
FROM alpine:3.20

# Core packages: supervisor + tini (process manager), tailscale binaries,
# shellinabox (web terminal), python3 (http server + utilities),
# shadow (for useradd/passwd), and useful dev tools.
RUN apk add --no-cache \
        ca-certificates \
        tini \
        supervisor \
        python3 \
        shadow \
        curl \
        git \
        vim \
        nano \
        openssh-client \
        htop \
        bash \
        coreutils \
        findutils \
        grep \
        tar \
        gzip \
        unzip \
        wget

# Install shellinabox (community package on Alpine edge)
RUN apk add --no-cache --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community \
        shellinabox

# Copy tailscale binaries from builder
COPY --from=tailscale-builder /tmp/tailscaled /usr/local/bin/tailscaled
COPY --from=tailscale-builder /tmp/tailscale   /usr/local/bin/tailscale

# Supervisor config
COPY supervisord.conf /etc/supervisor/conf.d/services.conf

# Entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Set up root password (override at runtime with ROOT_PASSWORD env var)
# Default is a placeholder — set ROOT_PASSWORD in Render env vars
ENV ROOT_PASSWORD=change-me
RUN echo "root:${ROOT_PASSWORD}" | chpasswd

# Workspace for the http server + persistent files
RUN mkdir -p /var/run/tailscale /workspace

# Status page shown at the Render URL
RUN printf '%s\n' \
  '<!DOCTYPE html>' \
  '<html><head><title>Tailscale Exit Node + Web Terminal</title>' \
  '<style>body{font-family:system-ui,sans-serif;max-width:600px;margin:50px auto;padding:0 20px;color:#333}' \
  '.status{background:#e8f5e9;padding:15px;border-radius:8px;border-left:4px solid #4caf50}' \
  'code{background:#f5f5f5;padding:2px 6px;border-radius:3px;font-family:monospace}</style></head>' \
  '<body><h1>Tailscale Exit Node is Running</h1>' \
  '<div class="status"><p>This node is active and available as an exit node for your tailnet.</p>' \
  '<p>Web terminal: <code>http://&lt;node-hostname&gt;:4200</code> via Tailnet</p></div>' \
  '<p>The shellinabox terminal listens on port 4200 and is reachable via your Tailnet ' \
  '(not the public Render URL). Use Tailscale SSH or a browser at the Tailscale hostname.</p>' \
  '</body></html>' > /workspace/index.html

WORKDIR /workspace

# Health check: verify tailscale is up
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD tailscale status >/dev/null 2>&1 || exit 1

# Render exposes one HTTP port (8080) for the status page.
# shellinabox on 4200 is only reachable via the Tailnet.
EXPOSE 8080 4200

ENTRYPOINT ["/sbin/tini", "--", "/docker-entrypoint.sh"]
