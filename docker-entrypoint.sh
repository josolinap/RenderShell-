#!/bin/sh
set -e

# Unset Kubernetes env vars (some hosts leak them; they confuse tailscaled)
unset KUBERNETES_SERVICE_HOST KUBERNETES_PORT KUBERNETES_PORT_443_TCP

# If ROOT_PASSWORD is set at runtime (via Render env vars), update the password.
# This lets you change the password without rebuilding the image.
if [ -n "${ROOT_PASSWORD}" ] && [ "${ROOT_PASSWORD}" != "change-me" ]; then
    echo "root:${ROOT_PASSWORD}" | chpasswd
    echo "[entrypoint] root password updated from ROOT_PASSWORD env var"
else
    echo "[entrypoint] WARNING: ROOT_PASSWORD not set or is 'change-me'"
    echo "[entrypoint] Set ROOT_PASSWORD in your Render environment variables"
fi

# Validate that TAILSCALE_AUTHKEY is set
if [ -z "${TAILSCALE_AUTHKEY}" ]; then
    echo "[entrypoint] WARNING: TAILSCALE_AUTHKEY is not set — node will not register"
    echo "[entrypoint] Set TAILSCALE_AUTHKEY in your Render environment variables"
fi

# Ensure sshd privilege separation directory exists
mkdir -p /run/sshd

# Start supervisord (manages tailscaled, tailscale-up, sshd, shellinabox, http-server)
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/services.conf
