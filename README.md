# Local LLM stack for Strix Halo + OpenCode

Dockerized [llama.cpp](https://github.com/ggml-org/llama.cpp) `llama-server` tuned for
**AMD Strix Halo (Ryzen AI MAX+ 395 / Radeon 8060S, gfx1151)** with 128 GiB unified
memory. Exposes an OpenAI-compatible endpoint that [OpenCode](https://opencode.ai)
(and anything else speaking `/v1/chat/completions`) can hit.

## Layout

```
Dockerfile             # custom llama.cpp build, ROCm 7.2.2, gfx1151, GGML_HIP_UMA
docker-compose.yaml    # rocm profile (default) + vulkan fallback profile
.env / .env.example    # MODEL_FILE, CTX_SIZE, LLAMA_HOST/PORT
opencode.json          # provider config -> http://127.0.0.1:8080/v1
scripts/fetch-model.sh # huggingface-cli download into ./models
models/                # GGUFs live here (gitignored)
```

## Prereqs (one-time)

System packages:
```sh
sudo pacman -S docker docker-compose docker-buildx python-pipx
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"   # log out + back in to pick up the group
pipx install 'huggingface_hub[cli]'
```

Kernel cmdline (systemd-boot): append `iommu=pt amdgpu.gttsize=126976` to the
`options` line in `/boot/loader/entries/<your>.conf`, then reboot. This unlocks
~124 GiB of GPU-addressable unified memory and turns on IOMMU pass-through.

## Quick start

```sh
cp .env.example .env             # tweak if you want
./scripts/fetch-model.sh         # ~32 GB download
docker compose up -d --build     # first build is slow (~15-25 min)
docker compose logs -f llama     # watch it warm up
curl http://127.0.0.1:8080/v1/models   # confirm endpoint
```

## OpenCode

Project-local config is already in `opencode.json`. To use it globally:

```sh
mkdir -p ~/.config/opencode
cp opencode.json ~/.config/opencode/opencode.json
opencode    # then `/models` in the TUI to pick `llama-local/qwen3-coder`
```

The provider points at `http://127.0.0.1:8080/v1`. If you bound the server to a
LAN/Tailscale IP via `LLAMA_HOST` in `.env`, change the `baseURL` accordingly.

## Day-to-day

```sh
docker compose up -d            # start
docker compose down             # stop
docker compose logs -f llama    # tail logs
docker compose ps               # status
docker compose restart llama    # restart after .env tweaks
docker compose up -d --build    # rebuild after Dockerfile changes
```

## Swapping models

Drop a GGUF into `./models/`, then either:

- edit `.env`: `MODEL_FILE=your-file.gguf` and `docker compose restart llama`, or
- override per-run: `MODEL_FILE=foo.gguf docker compose up -d`

Convenience downloads via `scripts/fetch-model.sh`:

```sh
# default — Qwen3-Coder 30B-A3B Q8 (recommended)
./scripts/fetch-model.sh

# Gemma 4 26B-A4B (MoE, multimodal-capable peer)
REPO=unsloth/gemma-4-26B-A4B-it-GGUF \
  FILE=gemma-4-26B-A4B-it-Q8_0.gguf \
  ./scripts/fetch-model.sh

# GLM-4.5-Air (~75 GB Q5, denser reasoning)
REPO=bartowski/zai-org_GLM-4.5-Air-GGUF \
  FILE=zai-org_GLM-4.5-Air-Q5_K_M.gguf \
  ./scripts/fetch-model.sh
```

After swapping, also update `opencode.json` model id + context limit so OpenCode
sees the new alias.

## ROCm vs Vulkan

ROCm is the default (best perf when stable). If a llama.cpp release regresses on
gfx1151, swap to the upstream Vulkan image — same endpoint, no rebuild:

```sh
docker compose down
docker compose --profile vulkan up -d
```

## Tuning knobs

In `docker-compose.yaml` `command:` block:

- `-c $CTX_SIZE` — context window. 65536 is conservative; try 131072 once stable.
- `-b 2048 -ub 512` — prompt-processing batch / micro-batch. Higher `-b` = faster
  prompt PP, more peak memory. Drop to `-b 1024 -ub 256` if you OOM.
- `-fa 1` — flash attention. **Keep on** for Strix Halo.
- `--no-mmap` — **keep on**; mmap'd pages are not UMA-friendly here.
- `-ngl 999` — offload all layers. UMA means there's no real "copy to VRAM" cost.
- `--n-cpu-moe N` — pin N MoE experts to CPU. Usually leave unset on UMA, but
  can help if you stack multiple models.

In `Dockerfile`:

- `ROCM_VERSION` arg — bump when a newer ROCm fixes something.
- `GPU_TARGETS=gfx1151` — explicit Strix Halo target. Don't add others; it
  bloats the build.

## Troubleshooting

**`docker compose build` fails to connect to docker.sock**
Daemon not running: `sudo systemctl enable --now docker`.

**`exec format error` / "no kernel image" in logs**
ROCm runtime didn't recognise gfx1151. Confirm `HSA_OVERRIDE_GFX_VERSION=11.5.1`
is set in compose env (it is by default), and that the host kernel/firmware
matches a ROCm-supported version. Worst case: switch to the Vulkan profile.

**OOM on model load**
Either drop the quant (Q8 → Q6_K → Q5_K_M), or shrink `CTX_SIZE`, or confirm
the kernel cmdline param `amdgpu.gttsize=126976` is actually live
(`cat /proc/cmdline`).

**`/v1/models` returns 404 or empty**
The model file path inside the container is `/models/$MODEL_FILE`. Check the
file actually exists in `./models/` and the filename in `.env` matches.

**OpenCode can't see the model**
Run `/models` in OpenCode TUI to refresh. The model id in `opencode.json` must
match `MODEL_ALIAS` from `.env` (default: `qwen3-coder`).

**Slow first token**
Cold-cache prompt processing; subsequent generations should be ~5-10× faster.
If it's still slow, check `docker stats` to confirm the container has GPU
access, and watch `radeontop` on the host while a request is in flight.
