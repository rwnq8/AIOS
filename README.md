# AIOS — AI-Driven Operating System Kernel

A bootable USB drive that autonomously builds an AI-native operating system
from a lightweight Linux base. **Zero user knowledge required.**

## What This Is

AIOS is a moonshot project to create a fully autonomous OS bootstrap process:

1. **Plug in a USB drive** — no installation, no configuration
2. **Boot** — Alpine Linux loads in seconds
3. **AI takes over** — local model (no cloud) detects hardware, sets up the
   environment, and begins building the OS kernel
4. **Done** — you have a working AI-native operating system

## Current Status: v0.1.0-p0 — Architecture & Planning

Phase 0 deliverables:
- [x] Architecture specification (`ARCHITECTURE.md`)
- [x] Bootstrap sequence specification (`BOOTSTRAP.md`)
- [x] Bootstrap script skeleton (`first_boot.sh`)
- [x] Orchestrator skeleton (`orchestrator.py`)
- [x] Launch script (`launch.sh`)

## Quick Start (When Built)

```bash
# 1. Download the AIOS image
# 2. Flash to USB (8GB+):
#    - Windows: Rufus or balenaEtcher
#    - Linux: dd if=aios.img of=/dev/sdX bs=4M
# 3. Boot from USB
# 4. Watch AIOS set itself up
```

## Architecture

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full architecture document.

```
USB Boot → Alpine Linux → first_boot.sh → llama.cpp + DeepSeek-Coder
                                         → orchestrator.py
                                         → Multi-agent ensemble
```

## Technical Stack

| Layer | Technology |
|:------|:-----------|
| Base OS | Alpine Linux (~5MB) |
| LLM Runtime | llama.cpp (CPU-optimized) |
| Primary Model | DeepSeek-Coder 1.3B GGUF |
| Reviewer Model | Granite-3.2-2B GGUF |
| Validator | AILO-152M GGUF |
| Orchestrator | Python 3.11+ |
| Build | Make + Python |

## Hardware Requirements

| Component | Minimum | Recommended |
|:----------|:--------|:------------|
| RAM | 4GB | 8GB+ |
| Storage | 8GB USB | 32GB USB |
| CPU | Dual-core 1.5GHz | Quad-core 2GHz+ |

## Design Principles

1. **Local-first** — no cloud, no API keys, no cost
2. **Zero-knowledge UX** — plug in, boot, done
3. **Ensemble safety** — multiple models cross-check each other
4. **CPU-only** — works on any laptop, no GPU required
5. **AI proposes, never executes unilaterally** — safety gatekeeper

## Research

Key projects to study:
- [agiresearch/AIOS](https://github.com/agiresearch/AIOS) — LLM Agent OS
- [PAI](https://github.com/nirholas/PAI) — Bootable USB with local Ollama
- [ClaudiOS](https://github.com/oraios/claudios) — Linux that boots into Claude
- [NIGHTRUN](https://github.com/hardrave/NIGHTRUN) — Bare-metal LLM runtime
- [ostk.ai](https://github.com/os-tack/ostk.ai) — Filesystem-coordinated AI agents

## License

MIT
