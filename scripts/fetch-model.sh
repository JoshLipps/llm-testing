#!/usr/bin/env bash
# Download a GGUF into ./models for the compose stack.
# Default: Qwen3-Coder-30B-A3B-Instruct Q8_0.
#
# Alternates worth trying on Strix Halo:
#   Gemma 4 26B-A4B (MoE, similar profile, multimodal+general):
#     REPO=unsloth/gemma-4-26B-A4B-it-GGUF FILE=gemma-4-26B-A4B-it-Q8_0.gguf ./scripts/fetch-model.sh
#   GLM-4.5-Air (dense-feel reasoning, ~75GB at Q5):
#     REPO=bartowski/zai-org_GLM-4.5-Air-GGUF FILE=zai-org_GLM-4.5-Air-Q5_K_M.gguf ./scripts/fetch-model.sh
#
# Override with: REPO=... FILE=... ./scripts/fetch-model.sh
set -euo pipefail

REPO="${REPO:-unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF}"
FILE="${FILE:-Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf}"
OUT_DIR="${OUT_DIR:-$(cd "$(dirname "$0")/.." && pwd)/models}"

mkdir -p "$OUT_DIR"

if ! command -v huggingface-cli >/dev/null 2>&1; then
    echo "huggingface-cli not found. Install with:  pipx install 'huggingface_hub[cli]'" >&2
    echo "(or:  uv tool install huggingface_hub)" >&2
    exit 1
fi

echo "Fetching $REPO :: $FILE -> $OUT_DIR"
huggingface-cli download "$REPO" "$FILE" \
    --local-dir "$OUT_DIR" \
    --local-dir-use-symlinks False

echo
echo "Done. Update MODEL_FILE in .env if you grabbed a different file."
ls -lh "$OUT_DIR/$FILE"
