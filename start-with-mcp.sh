#!/bin/bash
# Start the MCP server (mcp-proxy -> comfy-mcp) in the background, then hand over to the
# original ComfyUI entrypoint. The final `exec` keeps ComfyUI in the main-process role.
#
# - The comfy-cli workspace is /root/ComfyUI. The original entrypoint copies it from the
#   image bundle at startup, so this script waits for it instead of using the bundle path.
# - COMFY_LOCAL_URL points at 127.0.0.1:8188 in the same container. comfy-cli only fetches
#   object_info from loopback literals (SSRF guard), so this value must stay a loopback address.
# - mcp-proxy needs --pass-environment; by default it starts the child with an empty environment.

export COMFY_LOCAL_URL="${COMFY_LOCAL_URL:-http://127.0.0.1:8188}"
MCP_PORT="${MCP_PORT:-8189}"

(
  # Wait until /root/ComfyUI exists (the original entrypoint copies it from the bundle)
  for _ in $(seq 1 120); do
    [ -f /root/ComfyUI/main.py ] && break
    sleep 1
  done
  comfy set-default /root/ComfyUI >/dev/null 2>&1 || \
    echo "[mcp] WARN: 'comfy set-default /root/ComfyUI' failed" >&2
  exec /opt/mcp-proxy-venv/bin/mcp-proxy --pass-environment \
    --host 0.0.0.0 --port "${MCP_PORT}" -- comfy-mcp
) &

exec bash /runner-scripts/entrypoint.sh
