#!/bin/bash
# Download the Whisper ggml model for speech-to-text.
#
# Usage: ./scripts/download-model.sh [output-dir] [model-size]
#
# model-size: tiny.en, base.en (default), small.en, medium.en
# Downloads from the ggerganov/whisper.cpp HuggingFace repo.
# base.en is ~148MB — good balance of speed and accuracy for short commands.

set -euo pipefail

MODEL_DIR="${1:-./models}"
MODEL_SIZE="${2:-base.en}"
MODEL_FILE="ggml-${MODEL_SIZE}.bin"
BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

mkdir -p "$MODEL_DIR"

dest="${MODEL_DIR}/${MODEL_FILE}"

if [ -f "$dest" ]; then
  echo "  ✓ ${MODEL_FILE} already exists at ${dest}"
  exit 0
fi

echo "Downloading Whisper ${MODEL_SIZE} model to ${dest}..."
echo ""
curl -fSL --progress-bar "${BASE_URL}/${MODEL_FILE}" -o "$dest"
echo ""
echo "Done. Model saved to ${dest}"
