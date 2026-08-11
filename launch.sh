#!/bin/sh
# AIOS Launch Script v0.1.0-p0
# Executed after chroot into persistence by first_boot.sh.
# Sets up the Python environment and starts the orchestrator.

echo "[AIOS] Launch sequence starting..."

# Activate Python virtual environment
if [ -f /aios/runtime/python/venv/bin/activate ]; then
    . /aios/runtime/python/venv/bin/activate
fi

# Verify orchestrator exists
if [ ! -f /aios/orchestrator.py ]; then
    echo "[FATAL] orchestrator.py not found at /aios/orchestrator.py"
    echo "[FATAL] Dropping to emergency shell..."
    exec /bin/sh
fi

# Set environment
export AIOS_ROOT=/aios
export AIOS_MODELS=/models
export PYTHONUNBUFFERED=1

# Log startup
mkdir -p /var/log/aios
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") AIOS launch v0.1.0-p0" >> /var/log/aios/boot.log

# Launch the orchestrator
echo "[AIOS] Starting orchestrator..."
exec python3 /aios/orchestrator.py
