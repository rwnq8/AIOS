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

# 2. Build the bootstrap tarball (downloads ~2GB of models)
python build-bootstrap.py

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

## Model Selection

| RAM | Primary | Reviewer | Validator | Total Size |
|:----|:--------|:---------|:----------|:-----------|
| 4GB | deepseek-coder-1.3b Q4_K_M (~800MB) | — | gemma-3-1b Q4_K_M (~500MB) | ~1.3GB |
| 8GB+ | deepseek-coder-1.3b Q4_K_M (~800MB) | granite-3.2-2b Q4_K_M (~1.2GB) | gemma-3-1b Q4_K_M (~500MB) | ~2.5GB |

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
