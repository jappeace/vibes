---
name: train-speech-model
description: >
  Train a Piper TTS voice model on a Vast.ai GPU instance. Use when fine-tuning
  text-to-speech models, preparing speech datasets, choosing base checkpoints,
  or deploying ML training to remote GPUs. Covers the full pipeline from dataset
  prep through ONNX export and quality testing.
user-invocable: true
argument-hint: "[accent/voice-name]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---


# Train Speech Model (Piper TTS on Vast.ai)

Fine-tune a Piper TTS model on a Vast.ai GPU instance. This skill encapsulates
hard-won deployment experience from training Scottish, British, and other accent
models.

## Step 0: Goal Clarification (MANDATORY)

**Training costs 5-8 hours of GPU time and ~$4-5. Getting the goal wrong wastes
all of it.** Before touching any code, use AskUserQuestion to nail down:

### Questions to ask the user:

1. **Accent intensity**: "How strong should the accent be?"
   - Light/hint (intelligible to all English speakers, subtle regional flavor)
   - Medium (clearly identifiable accent, natural-sounding)
   - Heavy/thick (strong regional character, may use dialect words, prioritize
     authenticity over universal intelligibility)

   This is THE most important question. V1 of Scottish TTS failed because we
   assumed "Scottish accent" meant medium, but the user wanted heavy. The
   difference changes base checkpoint choice, training data strategy, and epoch
   count.

2. **Target speaker profile**: "Describe the voice you want."
   - Gender (male/female)
   - Age range (young adult, middle-aged, elderly)
   - Specific voice qualities (warm, authoritative, friendly, etc.)

   This determines which base checkpoint to start from and which dataset
   speakers to include.

3. **Use case**: "What will this voice be used for?"
   - Narration/audiobooks
   - Voice assistant / smart home
   - Game character
   - Accessibility tool
   - Art project / fun

   Use case affects quality vs. character trade-offs. A voice assistant needs
   clarity; a game character can be more exaggerated.

4. **Reference examples** (optional): "Do you have any audio examples or
   characters that sound like what you want?"
   - YouTube clips, movie characters, real people
   - Helps calibrate accent intensity expectations

### How answers affect training decisions:

| Decision | Light accent | Heavy accent |
|----------|-------------|--------------|
| Base checkpoint | Neutral (en_US/lessac) | Closest regional match (en_GB/alba for Scottish) |
| Training data | Can mix real + synthetic | Real accent data ONLY, no synthetic |
| Chatterbox augmentation | Yes, safe to use | **NO** — dilutes accent (proven in v1) |
| Epochs | 2000-3000 new | 4000-5000 new |
| Dataset filtering | All speakers OK | Filter for strongest accent speakers |

### Example clarification dialogue:

> "I want a Scottish TTS voice"
>
> Before I start training (~5 hours, ~$4 GPU cost), let me make sure I get
> this right:
>
> 1. How strong should the Scottish accent be? Light hint, clearly Scottish,
>    or thick/heavy like a Glaswegian?
> 2. Male or female voice? Any age preference?
> 3. What's it for — voice assistant, narration, game, or something else?

**DO NOT proceed to training until the user has confirmed accent intensity.**

## Quick Start (after goal clarification)

1. Prepare a training script (see [onstart-template.md](onstart-template.md))
2. Rent an RTX 4090 on Vast.ai using `--entrypoint` mode (NOT SSH)
3. Monitor with `vastai logs INSTANCE_ID`
4. Download ONNX model when done
5. Destroy instance

## Architecture Decision: --entrypoint Mode

**ALWAYS use `--entrypoint` mode, NOT SSH.** SSH port forwarding on Vast.ai is
unreliable across providers (tested: Mexico, Washington, UK, Texas — all broken).

```bash
# Compress script to fit 4048-char onstart-cmd limit
SCRIPT=$(gzip -c onstart.sh | base64 -w0)
vastai create instance OFFER_ID \
  --image pytorch/pytorch:2.1.0-cuda11.8-cudnn8-runtime \
  --disk 100 \
  --onstart-cmd "echo '$SCRIPT' | base64 -d | gunzip > /root/run.sh && bash /root/run.sh"
```

If the script exceeds 4048 chars after compression, use `--entrypoint` instead:
```bash
vastai create instance OFFER_ID \
  --image pytorch/pytorch:2.1.0-cuda11.8-cudnn8-runtime \
  --disk 100 \
  --entrypoint /bin/bash \
  --args -c "apt-get update && apt-get install -y wget && wget -O /root/run.sh 'RAW_GITHUB_URL' && bash /root/run.sh"
```

## Choosing a Base Checkpoint

Base checkpoint choice is THE most important decision for accent quality:

| Goal | Base Checkpoint | Rationale |
|------|----------------|-----------|
| Scottish female | en_GB/alba (epoch 4179) | British RP is phonetically closest to Scottish |
| Scottish male | en_GB/alba + more epochs | Same base, longer training |
| American accent | en_US/lessac (epoch 2164) | Native American voice |
| Generic English | en_US/lessac | Well-converged, neutral |

**Key insight**: An American base (en_US/lessac) fights Scottish phonetics.
A British base (en_GB/alba) requires a much smaller phonetic shift. Always pick
the base closest to your target accent.

HuggingFace paths: `rhasspy/piper-checkpoints` dataset repo, e.g.:
- `en/en_GB/alba/medium/epoch=4179-step=2101090.ckpt`
- `en/en_US/lessac/medium/epoch=2164-step=1355540.ckpt`

## Training Data Rules

### Minimum sample count

Piper TTS fine-tuning needs at least ~500 utterances to converge well. Under 300
is risky — the model may not generalize. If your real dataset is too small,
you have two options:

### Option A: Synthetic augmentation with Chatterbox TTS

[Chatterbox TTS](https://github.com/resemble-ai/chatterbox) is a voice cloning
model that can generate new utterances in a target speaker's voice from just a
few seconds of reference audio.

```bash
pip install chatterbox-tts
python3 -c "
from chatterbox.tts import ChatterboxTTS
model = ChatterboxTTS.from_pretrained()
# reference_audio = a clean WAV of the target speaker
wav = model.generate('New sentence to say', audio_prompt='reference.wav')
"
```

**CRITICAL trade-off — accent intensity vs. sample count:**

| Accent goal | Use Chatterbox? | Why |
|-------------|----------------|-----|
| Heavy/thick | **NO** | Chatterbox clones voice timbre but NOT accent. Every synthetic sample dilutes the accent toward generic English. V1 Scottish TTS proved this — 619 synthetic samples mixed with 894 real ones produced a weak, watered-down accent. |
| Medium | **Maybe** | Small amounts (~20-30% synthetic) may be OK if real data is very scarce (<400 samples). Monitor accent quality at checkpoints. |
| Light/hint | **Yes** | When accent authenticity isn't the priority, synthetic augmentation safely boosts sample count. Can double or triple your dataset. |

**If the user wants a heavy accent: do NOT use Chatterbox. Period.**
If they want light/medium and you have <400 real samples, augmentation is
reasonable but keep synthetic ratio under 30%.

### Option B: Add more real speakers

For heavy accents with too few samples from one speaker, prefer adding a second
real speaker from the same accent region over synthetic augmentation:
- OpenSLR 83 Scottish male: 1,649 utterances (vs 894 female)
- May need `--resume_from_single_speaker_checkpoint` flag or multi-speaker setup

### Data format notes

1. **OpenSLR 83** is the go-to for Scottish English (894 female, 1649 male utterances)
2. **CSV format**: `sentence_id, wav_filename, transcript` (3 columns, comma-separated)
3. **LJSpeech format** for Piper: `utterance_id|transcript_text` in metadata.csv
4. **Resample to 22050 Hz mono** with sox before preprocessing

## Critical Dependency Pins

These MUST be pinned or training will fail in subtle ways:

```bash
pip install 'pip==23.3.2'           # pip>=24.1 rejects PL metadata
pip install 'numpy<2'               # numpy 2.0 removed np.Inf
pip install pytorch-lightning==1.7.7 # Piper requires this exact version
pip install torchmetrics==0.11.4    # _compare_version removed in newer
pip install cython                  # build_monotonic_align.sh needs it
pip install librosa                 # piper_train.norm_audio needs it
pip install piper-phonemize         # not auto-installed by piper
```

**DO NOT pip install torch** — use the container's pre-installed PyTorch.
Installing torch via pip can pull a version incompatible with the CUDA driver.

## PyTorch Lightning 1.7.7 Patches

PL 1.7.7 needs three patches to work with modern PyTorch:

```bash
PL=/opt/conda/lib/python3.10/site-packages/pytorch_lightning

# 1. weights_only=False for torch.load (torch 2.x default changed)
sed -i 's/return torch.load(f, map_location=map_location)/return torch.load(f, map_location=map_location, weights_only=False)/' \
  "$PL/utilities/cloud_io.py"

# 2. Skip LR scheduler validation (crashes with Piper's NoamLR)
sed -i '/def _validate_scheduler_api/a\    return  # patched' \
  "$PL/core/optimizer.py"

# 3. Limit onnxruntime threads (prevents container process limit crash)
sed -i 's/self.session = onnxruntime.InferenceSession(onnx_path)/opts = onnxruntime.SessionOptions(); opts.inter_op_num_threads = 1; opts.intra_op_num_threads = 1; self.session = onnxruntime.InferenceSession(onnx_path, sess_options=opts)/' \
  /root/piper/src/python/piper_train/norm_audio/vad.py 2>/dev/null || true
```

**IMPORTANT**: Find the ACTUAL PL install path. Don't use `python -c "import pytorch_lightning; print(...)"` —
the runtime path may differ from the import path. Use the known conda path for
the `pytorch/pytorch:2.1.0-cuda11.8-cudnn8-runtime` image.

## Container Restart Resilience

Vast.ai containers restart on script failure. Make EVERYTHING idempotent:

```bash
# Git clone — skip if already cloned
[ -d piper ] || git clone https://github.com/rhasspy/piper.git

# Dataset download — skip if already downloaded
[ -f data.zip ] || wget -O data.zip "$URL"

# Preprocessing — skip if already done
[ -f /root/training/dataset.jsonl ] || python3 -m piper_train.preprocess ...

# CRITICAL: Resume from latest checkpoint, not base
RESUME_CKPT="/root/base.ckpt"
if [ -d "/root/training/lightning_logs" ]; then
    LATEST=$(find /root/training/lightning_logs -name "epoch=*.ckpt" 2>/dev/null | \
        sed 's/.*epoch=\([0-9]*\).*/\1 &/' | sort -n | tail -1 | cut -d' ' -f2-)
    [ -n "$LATEST" ] && RESUME_CKPT="$LATEST"
fi
```

Also: `export DEBIAN_FRONTEND=noninteractive` or apt-get hangs on tzdata.

## Training Parameters

```bash
python3 -m piper_train \
  --dataset-dir /root/training \
  --accelerator gpu \
  --devices 1 \
  --batch-size 32 \
  --max_epochs 8000 \
  --resume_from_checkpoint "$RESUME_CKPT" \
  --checkpoint-epochs 50 \
  --precision 32 \
  --validation-split 0.0 \
  --num-test-examples 0
```

- **checkpoint-epochs 50**: Balance between disk usage (~30GB for 76 checkpoints)
  and restart resilience (max 50 epochs lost = ~5 min on RTX 4090)
- **max_epochs**: Set to base_epoch + desired_new_epochs (e.g., 4179 + 3821 = 8000)
- **batch-size 32**: Good for RTX 4090 with medium quality VITS
- **precision 32**: fp16 can cause NaN with VITS models
- **validation-split 0.0**: Small datasets don't benefit from validation holdout

## ONNX Export

Find the best checkpoint across ALL training versions (handles restarts):

```bash
CKPT_DIR="/root/training/lightning_logs"
BEST=$(find "$CKPT_DIR" -name "epoch=*.ckpt" 2>/dev/null | \
    sed 's/.*epoch=\([0-9]*\).*/\1 &/' | sort -n | tail -1 | cut -d' ' -f2-)
python3 -m piper_train.export_onnx "$BEST" /root/model.onnx
cp /root/training/config.json /root/model.onnx.json
```

## Accent Quality Testing

Generate diagnostic audio targeting specific phonetic markers:

| Category | Test Sentence | What to Listen For |
|----------|--------------|-------------------|
| Rolled R | "The road runs right round the reservoir." | Rhotic /r/ |
| Velar fricative | "It was a braw bricht moonlicht nicht." | /x/ in loch, bricht |
| Scottish vowels | "Go home and don't come alone." | GOAT vowel |
| Scottish phrases | "Aye, it's a bonnie wee loch up in the highlands." | Natural rhythm |
| Prosody | "Will you be coming to Edinburgh for Hogmanay then?" | Rising intonation |

```bash
echo "Test sentence here" | piper --model /root/model.onnx --output_file test.wav
```

## Cost Estimates (RTX 4090)

- ~28 steps/epoch, ~600-700 epochs/hour
- 3800 new epochs = ~5.5 hours training
- Instance cost: ~$0.60-0.70/hr = ~$3.50-4.00 total
- Setup time: ~15-20 minutes (deps, download, preprocess)

## GPU Selection

```bash
vastai search offers 'gpu_name=RTX_4090 gpu_ram>23 reliability>0.95 disk_space>100' \
    -o 'dph-' --limit 5
```

- RTX 4090: Best price/performance for Piper TTS
- 100GB disk minimum (checkpoints + dataset + model)
- Image: `pytorch/pytorch:2.1.0-cuda11.8-cudnn8-runtime` (known working)

## Monitoring

```bash
vastai logs INSTANCE_ID              # Stream logs
vastai show instance ID --raw        # Instance status JSON
```

Look for checkpoint saves in logs:
```
DEBUG:fsspec.local:open file: .../epoch=NNNN-step=SSSSSS.ckpt
```

Training complete marker: `MARKER: TRAINING_DONE`

## Files Reference

- [onstart-template.md](onstart-template.md) — Full self-contained training script template
- [openslr-datasets.md](openslr-datasets.md) — Available speech datasets and formats
