# AIOS Bootstrap Sequence — Technical Specification

## Overview

The AIOS bootstrap is a fully autonomous startup sequence that transforms a raw
USB boot into a functioning AI-native OS environment. The design principle is
**zero-interaction**: the user plugs in the USB and boots. Everything else is
automatic.

## Boot Flow

### Stage 0: BIOS/UEFI → GRUB

```
Power On → BIOS/UEFI → USB Boot → GRUB
```

GRUB configuration (`grub.cfg`):
```
menuentry "AIOS — AI-Driven OS" {
    linux /boot/vmlinuz-lts root=UUID=AIOS-ROOT ro quiet loglevel=3
    initrd /boot/initramfs-lts
}
```

### Stage 1: Linux Kernel → initramfs → first_boot.sh

The initramfs contains a minimal Alpine Linux root filesystem with:
- BusyBox
- `first_boot.sh` (the bootstrap script)
- `aios-bootstrap.tar.gz` (llama.cpp, models, Python, orchestrator)

`first_boot.sh` performs:

1. **Hardware Detection**
   ```bash
   TOTAL_RAM=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
   CPU_CORES=$(nproc)
   DISK_DEV=$(lsblk -ndo NAME,SIZE | sort -k2 -hr | head -1 | awk '{print $1}')
   ```

2. **Model Selection** (based on RAM)
   ```bash
   if [ $TOTAL_RAM -lt 4096 ]; then
       MODEL="gemma-3-1b-it-Q4_K_M"      # 806MB, works on 4GB
   elif [ $TOTAL_RAM -lt 8192 ]; then
       MODEL="deepseek-coder-1.3b-instruct.Q4_K_M"  # 874MB, needs 4-6GB
   else
       MODEL="deepseek-coder-1.3b-instruct.Q4_K_M"  # Primary
       REVIEWER="granite-3.2-2b-instruct-Q4_K_M"    # Reviewer if RAM allows
   fi
   ```

3. **Persistence Partition** (creates ext4 partition for state)
4. **Extract bootstrap tarball** to persistence
5. **Switch root** to persistence
6. **Launch orchestrator.py**

### Stage 2: orchestrator.py

The Python orchestrator is the "brain" of AIOS. It:
1. Loads llama.cpp with the selected model
2. Initializes the Agent Registry
3. Starts the console interface

## File Layout (on USB after bootstrap)

```
/mnt/persist/
├── boot/
│   └── vmlinuz-lts          # Kernel
├── models/
│   ├── deepseek-coder-1.3b-instruct.Q4_K_M.gguf
│   ├── granite-3.2-2b-instruct-Q4_K_M.gguf
│   └── gemma-3-1b-it-Q4_K_M.gguf
├── runtime/
│   ├── llama.cpp/
│   │   └── llama-cli        # llama.cpp executable
│   └── python/
│       └── venv/            # Python virtualenv
├── aios/
│   ├── orchestrator.py      # Main orchestrator
│   ├── agents/
│   │   ├── primary.py       # Primary agent
│   │   ├── reviewer.py      # Reviewer agent
│   │   └── validator.py     # Validator agent
│   ├── consensus.py         # Consensus engine
│   ├── gatekeeper.py        # Safety gatekeeper
│   └── tools/
│       ├── file_ops.py      # File read/write tools
│       ├── shell.py         # Shell execution
│       └── git_ops.py       # Git operations
├── var/
│   └── log/
│       └── aios/
│           └── actions.log  # Action audit log
└── etc/
    └── aios.conf            # Runtime configuration
```

## Safety Architecture

### Gatekeeper Rules (gatekeeper.py)

```python
SAFE_OPERATIONS = ["read", "list", "status", "cat", "ls", "git log"]
DANGEROUS_OPERATIONS = ["write", "install", "build", "make", "git clone"]
DESTRUCTIVE_OPERATIONS = ["delete", "format", "rm", "dd", "mkfs"]

def evaluate(command: str) -> str:
    """Returns: 'safe', 'dangerous', or 'destructive'"""
    # Never let AI modify: /boot, /sys, /proc, /dev
    if any(p in command for p in ["/boot", "/sys", "/proc/", "/dev/"]):
        return "destructive"
    ...
```

### Agent Communication Protocol

All agent-to-agent communication uses a structured JSON protocol:
```json
{
  "from": "primary",
  "to": "reviewer",
  "type": "code_review_request",
  "payload": {
    "code": "...",
    "language": "c",
    "context": "Building kernel module"
  },
  "timestamp": "2026-08-11T...",
  "session_id": "uuid"
}
```

## Version

Current: **v0.1.0-p0** (Bootstrap specification — synchronized with ARCHITECTURE.md)
