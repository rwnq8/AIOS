#!/bin/sh
# build-llama.sh — compile llama.cpp and stage the runtime for the AIOS bootstrap.
# Run INSIDE the WSL2 Alpine build distro (same one that built the ISO):
#   wsl -d Alpine -e sh /mnt/c/<path-to-repo>/scripts/build-llama.sh
#
# Produces: /build/llama-runtime/llama.cpp/llama-cli — the binary orchestrator.py
# expects at runtime/llama.cpp/llama-cli inside the bootstrap tarball.
#
# Gotchas (learned 2026-08-13, each cost a failed build):
#   1. The `llama-cli` target NO LONGER EXISTS — the unified CLI target is `llama-app`,
#      and the produced binary is `build/bin/llama`.
#   2. `llama-app` links `llama-server-impl` + `llama-cli-impl` — those targets are
#      gated behind `-DLLAMA_BUILD_SERVER=ON -DLLAMA_BUILD_CLI=ON` (with EXAMPLES=ON).
#      With SERVER=OFF (or CLI=OFF) the link fails: "cannot find -lllama-server-impl".
#   3. Alpine needs `linux-headers`: common/arg.cpp includes <linux/limits.h>.
set -e
LOG=/build/llama_build.log
echo "START $(date)" > "$LOG"

echo "[1/4] install toolchain + headers"
apk add --no-cache build-base cmake git ninja linux-headers >> "$LOG" 2>&1

echo "[2/4] clone llama.cpp (shallow)"
cd /build
if [ ! -d llama.cpp ]; then
  git clone --depth 1 https://github.com/ggml-org/llama.cpp.git >> "$LOG" 2>&1
fi
cd llama.cpp

echo "[3/4] cmake configure (app target needs SERVER + CLI impls)"
cmake -B build \
  -DLLAMA_CURL=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=ON \
  -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_BUILD_CLI=ON >> "$LOG" 2>&1

echo "[4/4] build llama-app"
cmake --build build --config Release -j"$(nproc)" --target llama-app >> "$LOG" 2>&1

# Stage it where the bootstrap tarball expects it
mkdir -p /build/llama-runtime/llama.cpp
cp build/bin/llama /build/llama-runtime/llama.cpp/llama-cli
chmod +x /build/llama-runtime/llama.cpp/llama-cli
/build/llama-runtime/llama.cpp/llama-cli --version
echo "RUNTIME READY: /build/llama-runtime/llama.cpp/llama-cli"
echo "END $(date)" >> "$LOG"
