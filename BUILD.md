# AIOS Build Guide v0.1.0-p0

## Prerequisites

- Docker (for ISO building)
- QEMU (for testing, optional)
- 20GB free disk space (for model downloads and build artifacts)
- 8GB USB drive (for deployment)

## Quick Build

```bash
# 1. Clone the repo
git clone https://github.com/rwnq8/AIOS.git
cd AIOS

# 2. Build the bootstrap tarball (downloads ~3.2GB of models)
python build-bootstrap.py

# 2b. If you already have the models (resume path), assemble the tarball directly:
python build-bootstrap.py --model-only   # download only, then run the tar assembly

# 3. Build the ISO (requires Docker)
docker build -t aios-builder .
docker run --rm -v "$(pwd)/output:/output" -v "$(pwd)/aios-bootstrap.tar.gz:/build/aios-bootstrap.tar.gz" aios-builder

# 4. Test in QEMU
qemu-system-x86_64 -m 4096 -cdrom output/aios-v0.1.0-p0.iso -boot d

# 5. Write to USB
sudo dd if=output/aios-v0.1.0-p0.iso of=/dev/sdX bs=4M status=progress
```

## Files

| File | Purpose |
|:-----|:--------|
| `ARCHITECTURE.md` | Full architecture specification |
| `BOOTSTRAP.md` | Bootstrap sequence specification |
| `first_boot.sh` | Initramfs bootstrap script (HW detect → model select → persistence) |
| `orchestrator.py` | Python orchestrator (llama.cpp wrapper + multi-agent ensemble) |
| `launch.sh` | Chroot launch script |
| `build-iso.sh` | Docker-based Alpine ISO builder |
| `Dockerfile` | Docker build environment for ISO creation |
| `build-bootstrap.py` | Downloads models and builds bootstrap tarball |

## Model Selection (verified sizes — 2026-08-11)

| RAM | Primary | Reviewer | Validator | Total Size |
|:----|:--------|:---------|:----------|:-----------|
| 4GB | deepseek-coder-1.3b Q4_K_M (874MB) | — | gemma-3-1b Q4_K_M (806MB) | ~1.7GB |
| 8GB+ | deepseek-coder-1.3b Q4_K_M (874MB) | granite-3.2-2b Q4_K_M (1545MB) | gemma-3-1b Q4_K_M (806MB) | ~3.2GB |

**Verified SHA256 (2026-08-11):**
```
04cebb6fafa40ae628cf6bfeb76032ec792852f54020c559ad0a56b9f2839118  models/deepseek-coder-1.3b-instruct.Q4_K_M.gguf
8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135  models/gemma-3-1b-it-Q4_K_M.gguf
9bc086149f093169fb8e3e7517cd31752bfd9d70e0e7bb3ab351c0a5386cf8c9  models/granite-3.2-2b-instruct-Q4_K_M.gguf
```

**Filename gotcha:** HuggingFace GGUF repos use HYPHEN in quant names
(`granite-3.2-2b-instruct-Q4_K_M.gguf`), NOT dots. A dot variant 404s.

## Bootstrap Tarball

`aios-bootstrap.tar.gz` (~3.1 GB gzip) — the artifact embedded in the initramfs:
- `models/` — 3 GGUF models
- `aios/` — first_boot.sh (0755), orchestrator.py, launch.sh (0755)
- `etc/aios.conf` — runtime config placeholder
- `checksums.sha256` — SHA256 of every model
- `MANIFEST.txt` — build metadata

## Testing

```bash
# Test with 4GB RAM simulation
qemu-system-x86_64 -m 4096 -cdrom output/aios-v0.1.0-p0.iso -boot d -nographic

# Test with 8GB RAM (full ensemble)
qemu-system-x86_64 -m 8192 -cdrom output/aios-v0.1.0-p0.iso -boot d -nographic

# Test with USB passthrough
qemu-system-x86_64 -m 4096 -cdrom output/aios-v0.1.0-p0.iso \
    -drive file=/dev/sdX,format=raw,if=none,id=usb-drive \
    -device usb-storage,drive=usb-drive
```
