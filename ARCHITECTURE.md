# AIOS — AI-Driven Operating System Kernel

## Project Vision

A bootable USB drive that, when inserted into any basic laptop, autonomously:
1. Boots into a lightweight Linux environment
2. Loads a **local** AI model (no cloud, no API keys, no cost)
3. The AI agent takes over and builds/assembles the OS kernel autonomously
4. **Zero user knowledge required** — plug in, boot, watch

## Definition of Done

| Phase | Deliverable | Success Metric |
|:------|:------------|:---------------|
| P0 — Proof of Concept | Bootable Alpine Linux USB + llama.cpp + DeepSeek-Coder 1.3B, works on 3 test machines | AI responds to prompts on all machines |
| P1 — Agent Framework | Python orchestrator + 2-agent consensus (Primary + Reviewer) | Two agents collaborate on simple code tasks |
| P2 — Autonomous Build | Agent clones repo, runs `make`, interprets errors, fixes code, re-attempts | Agent builds a C program from source autonomously |
| P3 — Ensemble | 3-agent MACV verification (Primary + Reviewer + Validator) | Ensemble catches 80%+ of hallucinations |
| P4 — Zero-Knowledge UX | Voice interface, self-healing, first-boot wizard in plain English | Non-technical user boots and sees "I'm setting up your AI OS..." |

## Architecture

### Layer Diagram

```
┌─────────────────────────────────────────────────────────┐
│                  LAYER 6: USER INTERFACE                 │
│  Phase 1: Terminal chat   Phase 4: Voice + TTS          │
├─────────────────────────────────────────────────────────┤
│            LAYER 5: TOOL & FILESYSTEM ACCESS             │
│  File ops | Package mgr | Git | Build tools             │
│  Safety: AI proposes, gatekeeper approves               │
├─────────────────────────────────────────────────────────┤
│         LAYER 4: MULTI-AGENT VERIFICATION (Phase 3)     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │ PRIMARY  │→│ REVIEWER │→│VALIDATOR │→ CONSENSUS     │
│  │Generator │  │ Auditor  │  │  Syntax   │   ENGINE     │
│  └──────────┘  └──────────┘  └──────────┘              │
│  Consensus: Weighted voting + Critic-Refine loop        │
├─────────────────────────────────────────────────────────┤
│           LAYER 3: AGENT ORCHESTRATOR (KERNEL)          │
│  Task Queue | Agent Registry | Consensus Engine         │
│  Memory/Context Manager | Tool Registry                 │
├─────────────────────────────────────────────────────────┤
│             LAYER 2: LOCAL LLM RUNTIME                  │
│  llama.cpp (CPU-optimized)                              │
│  Primary: DeepSeek-Coder 1.3B GGUF (Q4_K_M)            │
│  Reviewer: Granite-3.2-2B or TinyLlama                  │
│  Validator: AILO-152M or Gemma-3-1B                     │
├─────────────────────────────────────────────────────────┤
│            LAYER 1: BOOTABLE FOUNDATION                 │
│  Alpine Linux (~5MB) | GRUB | initramfs                 │
│  first_boot.sh: HW detect → partition → install → boot  │
└─────────────────────────────────────────────────────────┘
```

### Technical Stack

| Layer | Technology | Rationale |
|:------|:-----------|:----------|
| Base OS | Alpine Linux | ~5MB, fastest boot, minimal overhead |
| Kernel | Linux LTS | Broad hardware support |
| Init | OpenRC | Lightweight, simple |
| LLM Runtime | llama.cpp | CPU-optimized, GGUF support |
| Primary Model | DeepSeek-Coder 1.3B GGUF | Best code quality vs. size |
| Critic Model | Granite-3.2-2B | Small but capable code reviewer |
| Validator | AILO-152M | 80MB, runs on anything |
| Orchestrator | Python 3.11+ | Flexible, widespread |
| Consensus | Custom Python module | Lightweight, no external deps |
| Build System | Make + Python | Simple, self-contained |

### Hardware Targets

| Component | Minimum | Recommended |
|:----------|:--------|:------------|
| RAM | 4GB | 8GB+ |
| Storage (USB) | 8GB | 32GB+ |
| CPU | Dual-core 1.5GHz | Quad-core 2GHz+ |
| GPU | None (CPU-only) | Intel/AMD iGPU |

### Model Performance Estimates

| Model | Size (Q4) | RAM Usage | Tokens/sec | Use |
|:------|:----------|:----------|:-----------|:----|
| AILO-152M | ~80MB | 200MB | 80-100 | Tiny validator |
| Gemma 3 1B | ~815MB | 1.2GB | 40-60 | Fallback primary |
| DeepSeek-Coder 1.3B | ~800MB | 1.5GB | 30-50 | Primary P0-P2 |
| Granite-3.2-2B | ~1.2GB | 2GB | 20-35 | Reviewer |
| Llama 3.2 3B | ~2GB | 3GB | 20-30 | Advanced P3+ |

### Storage Budget (8GB USB)

| Component | Size |
|:----------|:-----|
| Alpine Linux + GRUB | ~500MB |
| llama.cpp + runtime | ~100MB |
| DeepSeek-Coder 1.3B GGUF | ~800MB |
| Granite-3.2-2B GGUF | ~1.2GB |
| AILO-152M GGUF | ~80MB |
| Python + orchestrator | ~200MB |
| Persistence / workspace | 2GB+ |
| **Total** | **~4.9GB** |

## Bootstrap Sequence

```
POWER ON
  │
  ▼
GRUB → Alpine Linux kernel (minimal)
  │
  ▼
initramfs → first_boot.sh executes:
  │
  ├─ 1. DETECT: RAM, CPU cores, disk, network (if any)
  ├─ 2. PARTITION: Create persistence partition (ext4)
  ├─ 3. MOUNT: Mount persistence at /mnt/persist
  ├─ 4. INSTALL: Copy llama.cpp, models, Python, orchestrator
  │     (from squashfs on USB → persistence)
  ├─ 5. CHROOT: Switch root to persistence
  │
  ▼
orchestrator.py starts:
  │
  ├─ Load llama.cpp + DeepSeek-Coder 1.3B
  ├─ If RAM < 4GB: fall back to Gemma-3-1B
  ├─ Greet user: "AIOS ready. I can build your OS kernel now."
  │
  ▼
Wait for user input / autonomous build task
```

## Key Design Decisions

### 1. Why Alpine Linux? (Not Debian/Ubuntu)
- **5MB base image** vs. 100MB+ for Debian minimal
- **OpenRC** not systemd — simpler, faster
- **musl libc** not glibc — smaller binary sizes
- **apk** package manager is fast and minimal

### 2. Why DeepSeek-Coder? (Not Llama)
- **Multi-head Latent Attention (MLA)**: Compresses KV cache — lower memory for same quality
- **DeepSeek Sparse Attention (DSA)**: Near-linear complexity for long contexts
- **Code-optimized**: Better at reading compiler errors, writing Makefiles, debugging
- **GGUF available**: Works with llama.cpp CPU inference

### 3. Why Ensemble? (Not single model)
- **Hallucination detection**: Single models hallucinate ~15-30% on complex tasks
- **Adversarial verification**: Reviewer catches errors the Primary missed
- **Cross-checking**: 2-model ensemble (Primary + Reviewer) catches ~80% of hallucinations
- **Resource scaling**: Ensemble members scale down (tiny validator uses only 80MB)

### 4. Why CPU-only? (Not GPU)
- **Universality**: Works on any laptop, not just those with NVIDIA GPUs
- **Budget**: Target is basic laptops ($300-500 range)
- **Simplicity**: No CUDA drivers, no GPU passthrough complexity
- **Sufficiency**: 1.3B model at 30-50 tok/sec is usable for system administration tasks

## Safety Architecture

### Principle: "AI Proposes, Never Executes Unilaterally"

```
Agent generates command
    │
    ▼
Gatekeeper (Python) evaluates:
    ├─ Is this a safe operation? (read, list, status)
    │   → EXECUTE immediately
    ├─ Is this a potentially dangerous operation? (write, install, build)
    │   → DISPLAY to user with explanation
    │   → WAIT for approval
    └─ Is this a destructive operation? (delete, format, kernel modify)
        → BLOCK, require explicit confirmation
```

### Sandbox Rules
- AI cannot write to `/boot`, `/sys`, `/proc` without explicit gatekeeper override
- AI cannot modify `first_boot.sh` or orchestrator code
- AI's file operations are logged to `/var/log/aios/actions.log`
- All model outputs are checksummed for reproducibility

## Development Roadmap

### Phase 0: Proof of Concept (Weeks 1-2)
- [ ] Create Alpine Linux bootable USB with GRUB
- [ ] Install llama.cpp + DeepSeek-Coder 1.3B GGUF
- [ ] Write `first_boot.sh` auto-config script
- [ ] Test on 3 different laptops (4GB, 8GB, 16GB RAM)
- [ ] Basic terminal chat interface working
- **Gate**: AI responds to "hello world" on all test machines

### Phase 1: Agent Framework (Weeks 3-4)
- [ ] Build Python orchestrator with Agent class
- [ ] Implement Primary Agent (wraps DeepSeek via llama.cpp)
- [ ] Implement Reviewer Agent (wraps TinyLlama/Granite)
- [ ] Create consensus engine (weighted voting)
- [ ] Tool registry: file read/write/execute, git, make
- **Gate**: Two agents collaborate on "write a hello world C program"

### Phase 2: Autonomous Build (Weeks 5-6)
- [ ] Agent clones a GitHub repo autonomously
- [ ] Agent runs `make` and interprets errors
- [ ] Agent modifies source code and re-attempts
- [ ] Agent detects missing dependencies and installs them
- **Gate**: Agent builds a C program from source without human intervention

### Phase 3: Ensemble Verification (Weeks 7-8)
- [ ] Implement 3-agent MACV (Primary + Reviewer + Validator)
- [ ] Critic-Refine loop with configurable iterations
- [ ] Adversarial testing suite (agent tries to break own code)
- [ ] Performance benchmarking across hardware tiers
- **Gate**: Ensemble catches 80%+ of hallucinations single agent misses

### Phase 4: Zero-Knowledge UX (Weeks 9-10)
- [ ] Voice interface (Whisper STT + Piper TTS)
- [ ] Progress indicators, plain-English status messages
- [ ] Error recovery and self-healing
- [ ] First-boot wizard: "Hi! I'm your AI OS. I'm setting things up..."
- **Gate**: Non-technical user boots and completes setup without documentation

## Key Risks & Mitigations

| Risk | Severity | Mitigation |
|:-----|:---------|:-----------|
| Slow inference on budget laptop | HIGH | Start with smallest model (DeepSeek 1.3B), aggressive Q4 quantization, async background processing |
| AI hallucinates destructive commands | HIGH | Gatekeeper with allowlist/blocklist; "AI proposes, never executes"; sandboxed tools |
| USB persistence failure | MEDIUM | Multiple fallback storage paths; auto-detect and retry on mount failure |
| Model download corruption | MEDIUM | SHA-256 checksums, retry logic, offline fallback model |
| User can't boot from USB | MEDIUM | Include simple visual boot guide on USB root (README.txt with screenshots) |
| Hardware incompatibility | LOW | Alpine Linux has broad hardware support; fallback kernel modules in initramfs |

## Research References

### Existing Projects to Study
- **agiresearch/AIOS**: LLM Agent Operating System (academic, most established)
- **PAI (Private AI)**: Bootable USB with local Ollama + Debian
- **ClaudiOS**: Minimal Linux that boots directly into Claude Code
- **NIGHTRUN**: Bare-metal LLM runtime, no OS underneath
- **TensorAgent OS**: Bootable Linux where AI agent IS the UI
- **ostk.ai**: Local-first OS for AI agents using filesystem coordination
- **RuVix Cognition Kernel**: Purpose-built kernel with native vector/graph support

### Key Papers
- "AIOS: LLM Agent Operating System" (Mei et al., 2024)
- "LLM as OS, Agents as Apps" (Ge et al., 2024)
- DeepSeek-Coder technical report (Guo et al., 2024)

## Version

Current: **v0.1.0-p0** (Architecture specification — Phase 0 bootstrap planning)
