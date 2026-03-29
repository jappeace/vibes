# Onstart Script Template

Self-contained training script for Vast.ai `--entrypoint` mode.
Handles container restarts gracefully via idempotent operations and checkpoint resumption.

## Template

```bash
#!/usr/bin/env bash
# onstart.sh — Self-contained Piper TTS training for Vast.ai
# Container image: pytorch/pytorch:2.1.0-cuda11.8-cudnn8-runtime
set -euo pipefail
exec > >(tee -a /root/training.log) 2>&1

echo "=== Training Started: $(date) ==="

# --- Phase 1: System Dependencies ---
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3-venv python3-dev build-essential \
    espeak-ng ffmpeg git sox wget unzip

# --- Phase 2: Python Environment ---
# Use container's pre-installed PyTorch — DO NOT pip install torch
pip install 'pip==23.3.2'
pip install 'numpy<2' pytorch-lightning==1.7.7 torchmetrics==0.11.4 \
    onnxruntime soundfile huggingface_hub piper-tts piper-phonemize \
    cython librosa

cd /root
[ -d piper ] || git clone https://github.com/rhasspy/piper.git
cd /root/piper/src/python
pip install --no-deps -e .
bash build_monotonic_align.sh

# --- Phase 3: Dataset ---
cd /root
mkdir -p dataset/wav

# Download dataset (idempotent)
if [ ! -f dataset_archive.zip ]; then
    wget -O dataset_archive.zip "YOUR_DATASET_URL"
fi
if [ ! -d raw_data ]; then
    unzip -o dataset_archive.zip -d raw_data
fi

# Parse transcript + resample WAVs
# Adapt this Python block to your dataset's CSV/TSV format
python3 << 'PYEOF'
import os, subprocess
wavdir = "raw_data"  # adjust path
count = 0
with open("raw_data/transcript.csv") as f, open("dataset/metadata.csv", "w") as out:
    for line in f:
        # Adjust parsing for your format:
        # OpenSLR 83: sentence_id, wav_filename, transcript (3 cols, comma-sep)
        parts = [p.strip() for p in line.split(',')]
        if len(parts) >= 3:
            uttid = os.path.basename(parts[1]).replace('.wav', '')
            text = ','.join(parts[2:]).strip()
        elif len(parts) == 2:
            uttid = os.path.basename(parts[0]).replace('.wav', '')
            text = parts[1].strip()
        else:
            continue
        wav = f"{wavdir}/{uttid}.wav"
        if os.path.exists(wav) and text:
            subprocess.run(
                ["sox", wav, "-r", "22050", "-c", "1", f"dataset/wav/{uttid}.wav"],
                check=True
            )
            out.write(f"{uttid}|{text}\n")
            count += 1
print(f"Prepared {count} utterances")
PYEOF

# --- Phase 4: Base Checkpoint ---
python3 -c "
from huggingface_hub import hf_hub_download
import shutil
path = hf_hub_download(
    repo_id='rhasspy/piper-checkpoints',
    filename='YOUR_CHECKPOINT_PATH',  # e.g., en/en_GB/alba/medium/epoch=4179-step=2101090.ckpt
    repo_type='dataset'
)
shutil.copy(path, '/root/base.ckpt')
print('Downloaded base checkpoint')
"

# --- Phase 5: Preprocessing (idempotent) ---
export OMP_NUM_THREADS=2
export OPENBLAS_NUM_THREADS=2
export MKL_NUM_THREADS=2

if [ ! -f /root/training/dataset.jsonl ]; then
    python3 -m piper_train.preprocess \
      --language "YOUR_LANG_CODE" \
      --input-dir /root/dataset \
      --output-dir /root/training \
      --dataset-format ljspeech \
      --single-speaker \
      --sample-rate 22050
else
    echo "Preprocessing already done, skipping."
fi

# --- Phase 6: Patch PL + Train ---
PL=/opt/conda/lib/python3.10/site-packages/pytorch_lightning
sed -i 's/return torch.load(f, map_location=map_location)/return torch.load(f, map_location=map_location, weights_only=False)/' \
    "$PL/utilities/cloud_io.py"
sed -i '/def _validate_scheduler_api/a\    return  # patched' \
    "$PL/core/optimizer.py"
sed -i 's/self.session = onnxruntime.InferenceSession(onnx_path)/opts = onnxruntime.SessionOptions(); opts.inter_op_num_threads = 1; opts.intra_op_num_threads = 1; self.session = onnxruntime.InferenceSession(onnx_path, sess_options=opts)/' \
    /root/piper/src/python/piper_train/norm_audio/vad.py 2>/dev/null || true

# Resume from latest checkpoint if container restarted
RESUME_CKPT="/root/base.ckpt"
CKPT_DIR="/root/training/lightning_logs"
if [ -d "$CKPT_DIR" ]; then
    LATEST=$(find "$CKPT_DIR" -name "epoch=*.ckpt" 2>/dev/null | \
        sed 's/.*epoch=\([0-9]*\).*/\1 &/' | sort -n | tail -1 | cut -d' ' -f2-)
    if [ -n "$LATEST" ]; then
        RESUME_CKPT="$LATEST"
        echo "RESUMING from existing checkpoint: $RESUME_CKPT"
    fi
fi

echo "Training from: $RESUME_CKPT"
python3 -m piper_train \
  --dataset-dir /root/training \
  --accelerator gpu \
  --devices 1 \
  --batch-size 32 \
  --max_epochs YOUR_MAX_EPOCHS \
  --resume_from_checkpoint "$RESUME_CKPT" \
  --checkpoint-epochs 50 \
  --precision 32 \
  --validation-split 0.0 \
  --num-test-examples 0

echo "Training finished at $(date)"

# --- Phase 7: Export ONNX ---
BEST_CKPT=""
LAST_VERSION=$(ls -d "$CKPT_DIR"/version_* 2>/dev/null | sort -t_ -k2 -n | tail -1)
if [ -n "$LAST_VERSION" ] && [ -f "$LAST_VERSION/checkpoints/last.ckpt" ]; then
    BEST_CKPT="$LAST_VERSION/checkpoints/last.ckpt"
fi
if [ -z "$BEST_CKPT" ]; then
    BEST_CKPT=$(find "$CKPT_DIR" -name "epoch=*.ckpt" 2>/dev/null | \
        sed 's/.*epoch=\([0-9]*\).*/\1 &/' | sort -n | tail -1 | cut -d' ' -f2-)
fi

echo "Exporting: $BEST_CKPT"
python3 -m piper_train.export_onnx "$BEST_CKPT" /root/model.onnx
cp /root/training/config.json /root/model.onnx.json

# --- Phase 8: Test ---
echo "Test sentence" | \
  piper --model /root/model.onnx --output_file /root/test.wav 2>/dev/null || true

echo "MARKER: TRAINING_DONE"
```

## Customization Points

Replace these placeholders:
- `YOUR_DATASET_URL` — URL to download your speech dataset
- `YOUR_CHECKPOINT_PATH` — HuggingFace path to base checkpoint
- `YOUR_LANG_CODE` — espeak-ng language code (e.g., `en-gb-scotland`, `en-us`)
- `YOUR_MAX_EPOCHS` — base_checkpoint_epoch + desired_new_epochs

## Available Language Codes

Piper uses espeak-ng language codes. Common ones:
- `en-us` — American English
- `en-gb` — British English (RP)
- `en-gb-scotland` — Scottish English
- `en-gb-x-rp` — Received Pronunciation
- `de` — German
- `fr-fr` — French
- `es` — Spanish
- `nl` — Dutch

## Available Base Checkpoints

All at `rhasspy/piper-checkpoints` (HuggingFace dataset repo):

| Voice | Path | Epochs | Quality |
|-------|------|--------|---------|
| en_GB/alba | `en/en_GB/alba/medium/epoch=4179-step=2101090.ckpt` | 4179 | British female |
| en_US/lessac | `en/en_US/lessac/medium/epoch=2164-step=1355540.ckpt` | 2164 | American male |
| en_US/amy | `en/en_US/amy/medium/...` | varies | American female |
| de_DE/thorsten | `de/de_DE/thorsten/medium/...` | varies | German male |

Browse full list: `huggingface-cli ls rhasspy/piper-checkpoints --repo-type dataset`
