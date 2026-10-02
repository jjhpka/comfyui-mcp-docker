# ComfyUI + comfy-mcp (official local MCP server) in a single container image.
# Base: yanwk/comfyui-boot:cu130-slim-v2 (Blackwell sm_120 compatible; do NOT use cu126).
#
# One container runs both ComfyUI (:8188) and the MCP server (:8189).
#   - comfy-mcp: Comfy's first-party local MCP server (stdio only)
#   - mcp-proxy: stdio -> HTTP bridge; spawns comfy-mcp as a subprocess and serves it on :8189
#
# Dual-venv layout:
#   - comfy-mcp 0.10.0 requires mcp>=2 (mcp<3,>=2)
#   - mcp-proxy 0.12.0 only supports the mcp 1.x API (request_ctx), which conflicts with mcp 2.x
#   -> the bridge (mcp-proxy) is installed with mcp 1.x in an isolated venv at /opt/mcp-proxy-venv,
#      while comfy-mcp lives in the system environment (mcp 2.x). When mcp-proxy spawns comfy-mcp,
#      it runs through the absolute shebang of /usr/local/bin/comfy-mcp (system python),
#      so the two environments never mix.
FROM yanwk/comfyui-boot:cu130-slim-v2

# System environment: comfy-mcp + comfy-cli (mcp 2.x is installed with them). Versions are pinned
# to the ones that were tested. torch/numpy/pydantic stay unchanged and `pip check` passes.
RUN pip install --no-cache-dir \
    "comfy-mcp==0.10.0" \
    "comfy-cli==1.22.0"

# Bridge-only venv: mcp-proxy + mcp 1.x (fully isolated from the system environment)
RUN python3 -m venv /opt/mcp-proxy-venv \
    && /opt/mcp-proxy-venv/bin/pip install --no-cache-dir \
        "mcp==1.30.0" \
        "mcp-proxy==0.12.0"

# Wrapper that starts mcp-proxy in the background before the original entrypoint
COPY start-with-mcp.sh /runner-scripts/start-with-mcp.sh
RUN chmod +x /runner-scripts/start-with-mcp.sh

ENV PATH="/usr/local/bin:${PATH}"

# Replace the original CMD (bash /runner-scripts/entrypoint.sh) with the wrapper
CMD ["bash", "/runner-scripts/start-with-mcp.sh"]
