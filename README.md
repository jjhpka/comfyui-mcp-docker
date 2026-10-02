# comfyui-mcp-docker

A Docker setup that runs ComfyUI and the official local MCP server [`comfy-mcp`](https://github.com/Comfy-Org/comfy-mcp) in a **single container**.
One container serves the ComfyUI UI (`:8188`) and an HTTP MCP endpoint (`:8189`), so AI agents such as Claude Code or Cursor can drive ComfyUI.

- Base image: [`yanwk/comfyui-boot:cu130-slim-v2`](https://hub.docker.com/r/yanwk/comfyui-boot) (CUDA 13.0, compatible with Blackwell / RTX 50 series)
- Added on top: `comfy-mcp` (39 tools), `comfy-cli`, and `mcp-proxy` (a stdio-to-HTTP bridge)
- Tested on: WSL2 + Docker Desktop, NVIDIA RTX 5070 (12 GB)

## Requirements

- Docker and Docker Compose
- An NVIDIA GPU and the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) (on WSL2, GPU support in Docker Desktop)

## Quick start

```bash
git clone https://github.com/jjhpka/comfyui-mcp-docker.git
cd comfyui-mcp-docker

# Create the data directories as your own user first.
# If Docker creates them, they end up owned by root.
mkdir -p storage/{models,custom_nodes,input,output,user,cache/hf-hub,cache/torch-hub,dot-cache,dot-config,dot-local}

docker compose up -d --build
```

- ComfyUI UI: http://127.0.0.1:8188
- MCP endpoint: http://127.0.0.1:8189/mcp (streamable-http), http://127.0.0.1:8189/sse (SSE)

The first start takes 1-2 minutes. A single failed `curl` right after start does not mean the container is broken; poll until you get HTTP 200.

```bash
docker compose logs -f comfyui     # logs
docker compose restart comfyui     # restart after config changes
docker compose build comfyui       # rebuild after editing Dockerfile or start-with-mcp.sh
docker compose down                # stop (storage/ is kept)
```

## Connect an MCP client

```bash
# Claude Code
claude mcp add --transport http comfy-mcp http://127.0.0.1:8189/mcp
```

For other clients, register `http://127.0.0.1:8189/mcp` as a remote (HTTP) MCP server.

## Security: there is no authentication

Neither ComfyUI nor the MCP server has authentication. Anyone who can reach the ports can run workflows,
and can install third-party code through ComfyUI-Manager and MCP tools such as `install_node`.

For that reason the default bind address is `127.0.0.1` (this machine only). To use it from other devices, create a `.env` file:

```bash
# .env  (ignored by git)
BIND_ADDR=0.0.0.0          # all interfaces; only on a network you trust
# BIND_ADDR=100.x.y.z      # bind to one specific IP, for example a Tailscale address
```

## Architecture

```
MCP client
   |  HTTP (streamable-http)
   v
:8189  mcp-proxy (isolated venv, mcp 1.x)
   |  stdio
   v
comfy-mcp (system python, mcp 2.x) -> comfy-cli -> 127.0.0.1:8188 (ComfyUI in the same container)
```

- `start-with-mcp.sh` starts mcp-proxy in the background and then `exec`s the original entrypoint.
- `comfy-mcp` only speaks stdio, so a bridge is needed to expose it over HTTP.

### Pitfalls found while building this

- **mcp version conflict**: `comfy-mcp 0.10.0` requires `mcp>=2`, while `mcp-proxy 0.12.0` imports `request_ctx`, which no longer exists in mcp 2.x.
  mcp-proxy is therefore installed with mcp 1.x in its own venv at `/opt/mcp-proxy-venv`.
- **`--pass-environment` is required**: by default mcp-proxy starts the child process with an empty environment.
- **Loopback-only SSRF guard**: the `nodes` and `validate_workflow` tools in comfy-cli only fetch `object_info` from a `127.0.0.1` or `localhost` literal.
  This is why the MCP server runs in the **same container** as ComfyUI.
- **`/root/ComfyUI` is not in the image**: the base image keeps the source in `/default-comfyui-bundle/ComfyUI`, and its entrypoint copies it to `/root/ComfyUI`.
  The wrapper script waits for that copy to finish and then runs `comfy set-default /root/ComfyUI`.

### Not verified

- The MCP tools `launch_comfyui`, `stop_comfyui`, `restart_comfyui`, `install_node` and `update_comfyui` have not been called.
  ComfyUI is the main process of the container, so tools that stop it may take the whole container down.
- GPUs other than the RTX 5070 have not been tested.

## Volumes (all host bind mounts)

Files under `storage/` survive removing the container. Models are not part of the image; you have to add them yourself.

| Container path | Host path | Purpose |
|---|---|---|
| `/root/ComfyUI/models` | `storage/models` | Checkpoints, VAE, LoRA, ControlNet, etc. |
| `/root/ComfyUI/custom_nodes` | `storage/custom_nodes` | Custom nodes |
| `/root/ComfyUI/input` | `storage/input` | Input images |
| `/root/ComfyUI/output` | `storage/output` | Generated output |
| `/root/ComfyUI/user` | `storage/user` | Workflows and settings |
| `/root/.cache/huggingface/hub` | `storage/cache/hf-hub` | Hugging Face model cache |
| `/root/.cache/torch/hub` | `storage/cache/torch-hub` | torch hub cache |
| `/root/.cache` | `storage/dot-cache` | Other caches |
| `/root/.config` | `storage/dot-config` | Configuration |
| `/root/.local` | `storage/dot-local` | pip user installs, etc. |

**Do not reorder the volumes in `docker-compose.yml`.** Mounting `/root/.cache` as a whole can hide the mounts below it,
so the more specific paths are declared first.

On WSL2, keep models on the native WSL filesystem (ext4), not on a Windows mount such as `/mnt/c` or `/mnt/d`. Model loading is much slower there.

## Image tag note

Blackwell (RTX 50) is `sm_120` and needs CUDA 12.8+ and a PyTorch cu130 build. If you switch the base image to a `cu126` tag,
it fails with "no kernel image is available".

## Licenses

The image contains the components below. Check each license before you distribute the image.

| Component | License |
|---|---|
| ComfyUI | GPL-3.0 |
| ComfyUI-Manager | GPL-3.0-only |
| comfy-cli | GPL-3.0-only |
| comfy-mcp | AGPL-3.0-or-later OR a commercial license from Comfy |
| mcp-proxy, mcp | MIT |
| Base image `yanwk/comfyui-boot` | Mulan PubL v2 |

PyTorch, CUDA and other NVIDIA components are covered by their own licenses.
