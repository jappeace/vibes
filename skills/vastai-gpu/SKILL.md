---
name: vastai-gpu
description: >
  Rent and manage Vast.ai GPU instances for ML training, inference, and ONNX export.
  Use when renting GPUs, running remote training jobs, transferring files to/from GPU instances,
  or managing Vast.ai instances. Covers CLI setup, SSH access, file transfer, and instance lifecycle.
user-invocable: false
---

# Vast.ai GPU Instance Management

## CLI Installation

The `vastai` CLI cannot be installed into the nix store. Use a Python venv:

```bash
python3 -m venv /tmp/vastai-venv
/tmp/vastai-venv/bin/pip install vastai
```

## Environment Variables

The vastai CLI crashes on import if it can't create `~/.cache` and `~/.config` directories.
Override these three env vars on every invocation:

```bash
XDG_CONFIG_HOME=/tmp/xdg_config XDG_CACHE_HOME=/tmp/xdg_cache HOME=/tmp/vastai_home /tmp/vastai-venv/bin/vastai <command>
```

Create the directories first:
```bash
mkdir -p /tmp/xdg_config /tmp/xdg_cache /tmp/vastai_home
```

## API Key

The API key lives at `/home/claude/vibes/.config/vastai/vast_api_key`. Copy it to the temp config:
```bash
mkdir -p /tmp/xdg_config/vastai
cp /home/claude/vibes/.config/vastai/vast_api_key /tmp/xdg_config/vastai/
```

Notify the user if it doesn't exist.
Make sure it exists before doing a plan!

## Searching for Instances

```bash
vastai search offers 'gpu_name=RTX_3090 num_gpus=1 reliability>0.95 inet_down>100 disk_space>=50' -o 'dph'
```

- GPU names use underscores: `RTX_3090`, `RTX_4090`, `A100_SXM4`
- `-o 'dph'` sorts by dollars per hour (cheapest first)
- For large model downloads, require `inet_down>500` to avoid stalled transfers
- `reliability>0.98` avoids flaky machines

## Creating an Instance

```bash
vastai create instance OFFER_ID --image pytorch/pytorch:2.4.1-cuda12.4-cudnn9-devel --disk 60 --ssh
```

- The `--ssh` flag is required for SSH access
- `pytorch/pytorch:2.4.1-cuda12.4-cudnn9-devel` is a good base image for training
- Instance takes 2-10 minutes to go from `loading` to `running`

## Polling Instance Status

```bash
vastai show instances          # human-readable table
vastai show instances --raw    # JSON output
```

Extract SSH connection details programmatically:
```bash
vastai show instances --raw | python3 -c "import json,sys; data=json.load(sys.stdin); print(data[0]['id'], data[0]['ssh_host'], data[0]['ssh_port'])"
```

Wait for `actual_status` to become `"running"` before connecting.

## SSH Key Setup

Register your SSH key with the Vast.ai account AND attach it to the instance:

```bash
vastai create ssh-key 'ssh-ed25519 AAAA... comment'
vastai attach ssh INSTANCE_ID 'ssh-ed25519 AAAA... comment'
```

Note: `attach ssh` is two words, not `attach-ssh`. The SSH key string is a positional argument, not a flag.

## SSH and SCP Access

SSH and SCP are not available in the base nix environment. Wrap every command with `nix-shell -p openssh`:

### SSH (lowercase -p for port):
```bash
nix-shell -p openssh --run "ssh -o StrictHostKeyChecking=no -p PORT root@sshN.vast.ai 'COMMAND'"
```

### SCP upload (uppercase -P for port):
```bash
nix-shell -p openssh --run "scp -o StrictHostKeyChecking=no -P PORT -r LOCAL_PATH root@sshN.vast.ai:/workspace/"
```

### SCP download:
```bash
nix-shell -p openssh --run "scp -o StrictHostKeyChecking=no -P PORT root@sshN.vast.ai:/workspace/REMOTE_FILE LOCAL_PATH"
```

### SSH helper script (for repeated use):
```bash
cat > /tmp/vssh.sh << SCRIPT
#!/bin/bash
nix-shell -p openssh --run "ssh -o StrictHostKeyChecking=no -p PORT root@sshN.vast.ai \"\$*\""
SCRIPT
chmod +x /tmp/vssh.sh
```

## Running Long Jobs

Use `nohup` with background execution for long-running tasks:

```bash
ssh ... 'nohup bash /workspace/train.sh > /workspace/train.log 2>&1 &'
```

Monitor progress:
```bash
ssh ... 'tail -50 /workspace/train.log'
```

## Shell Quoting

Running Python code over SSH through nix-shell creates multi-level quoting nightmares.
When commands get complex, write them to a local file, SCP to the instance, then execute:

```bash
# Write script locally
cat > /tmp/my_script.py << 'EOF'
import torch
# ... complex code ...
EOF

# Upload
nix-shell -p openssh --run "scp -o StrictHostKeyChecking=no -P PORT /tmp/my_script.py root@sshN.vast.ai:/workspace/"

# Execute
nix-shell -p openssh --run "ssh -o StrictHostKeyChecking=no -p PORT root@sshN.vast.ai 'cd /workspace && python3 my_script.py'"
```

## Destroying Instances

Always destroy instances when done to stop billing:

```bash
vastai destroy instance INSTANCE_ID
```

## Common Gotchas

1. **HuggingFace downloads stall**: Large model downloads (>1GB) can hang on low-bandwidth machines. If a download stalls, destroy the instance and rent one with `inet_down>500`.

2. **Pre-installed PyTorch conflicts**: The pytorch Docker images have system-level torch. If installing packages that need a different torch version (e.g., ChatterBox TTS), create a separate venv:
   ```bash
   python3 -m venv /workspace/my-venv --system-site-packages
   source /workspace/my-venv/bin/activate
   ```

3. **SSH intermittent failures (exit code 255)**: Vast.ai SSH proxies occasionally drop connections. Just retry. The Vast.ai banner says "If authentication fails, try again after a few seconds."

4. **Missing system packages**: The pytorch Docker image is minimal. You'll likely need:
   ```bash
   apt-get update && apt-get install -y espeak-ng libespeak-ng-dev build-essential
   ```

5. **Working directory**: All files go under `/workspace/` which persists for the instance lifetime.

6. **PyTorch 2.6+ PosixPath issue**: Loading old checkpoints fails with `Unsupported global: GLOBAL pathlib.PosixPath`. Fix by converting PosixPaths to strings:
   ```python
   import torch
   from pathlib import PosixPath
   torch.serialization.add_safe_globals([PosixPath])
   ckpt = torch.load("model.ckpt", map_location="cpu")
   ```

7. **ONNX export dynamo issues**: PyTorch 2.6+ defaults to `dynamo=True` for `torch.onnx.export`, which requires `onnxscript` and often fails on VITS models. Force legacy export:
   ```python
   torch.onnx.export(..., dynamo=False)
   ```

## Typical Workflow

1. Install CLI, configure API key
2. Search offers, create instance
3. Poll `show instances` until status is `running`
4. Register SSH key with `create ssh-key` and `attach ssh`
5. Upload data/scripts via SCP
6. Run training via `nohup`, monitor with `tail`
7. Download results via SCP
8. Destroy instance immediately
