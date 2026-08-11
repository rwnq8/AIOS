#!/bin/sh
# AIOS Bootstrap Script v0.1.0-p0
# Runs inside initramfs on first boot from USB.
# Detects hardware, selects model, creates persistence, launches orchestrator.

set -e

# PID 1 must NEVER exit - any unexpected failure drops to emergency shell
trap 'err "Fatal error at line $LINENO. Dropping to emergency shell..."; exec /bin/sh' ERR

# === Color output ===
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[AIOS]${NC} $1"; }
warn() { echo -e "${YELLOW}[AIOS]${NC} $1"; }
err()  { echo -e "${RED}[AIOS]${NC} $1"; }

log "AIOS Bootstrap v0.1.0-p0 starting..."
log "========================================="

# Root is read-only squashfs - mount writable tmpfs for scratch
mount -t tmpfs tmpfs /tmp 2>/dev/null || true
log "========================================="

# === Stage 1: Hardware Detection ===
log "Detecting hardware..."

TOTAL_RAM=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo "0")
CPU_CORES=$(nproc 2>/dev/null || echo "1")
CPU_MODEL=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null | xargs || echo "unknown")

log "  RAM:        ${TOTAL_RAM} MB"
log "  CPU cores:  ${CPU_CORES}"
log "  CPU model:  ${CPU_MODEL}"

# === Stage 2: Model Selection ===
log "Selecting AI model based on available RAM..."

MODEL="gemma-3-1b-it-Q4_K_M"       # Default: smallest fallback
REVIEWER_MODEL=""            # No reviewer by default
VALIDATOR_MODEL="gemma-3-1b-it-Q4_K_M"  # Validator (only on RAM-constrained systems, same model reused)

if [ "$TOTAL_RAM" -ge 4096 ]; then
    MODEL="deepseek-coder-1.3b-instruct.Q4_K_M"
    log "  Selected PRIMARY: deepseek-coder-1.3b-instruct.Q4_K_M (4GB+ RAM)"
elif [ "$TOTAL_RAM" -ge 2048 ]; then
    MODEL="gemma-3-1b-it-Q4_K_M"
    log "  Selected PRIMARY: gemma-3-1b-it-Q4_K_M (2-4GB RAM)"
else
    MODEL="gemma-3-1b-it-Q4_K_M"
    VALIDATOR_MODEL=""
    warn "  Low RAM detected (< 2GB). Using light model. Expect slow responses."
fi

if [ "$TOTAL_RAM" -ge 8192 ]; then
    REVIEWER_MODEL="granite-3.2-2b-instruct-Q4_K_M"
    log "  Selected REVIEWER: granite-3.2-2b-instruct-Q4_K_M (8GB+ RAM)"
fi

# === Stage 3: Find Persistence Disk ===
log "Locating persistence storage..."

# Ensure storage drivers are loaded (USB, SCSI, SATA) before scanning
modprobe usb-storage 2>/dev/null || true
modprobe uhci_hcd 2>/dev/null || true
modprobe ehci_hcd 2>/dev/null || true
modprobe xhci_hcd 2>/dev/null || true
modprobe sd_mod 2>/dev/null || true
modprobe ahci 2>/dev/null || true
modprobe ata_piix 2>/dev/null || true
sleep 3

# Try to find a USB/disk device >= 8GB (exclude loop/ram/sr)
USB_DEV=""
for dev in /dev/sd? /dev/hd? /dev/vd?; do
    [ -b "$dev" ] || continue
    SIZE=$(blockdev --getsize64 "$dev" 2>/dev/null || echo "0")
    if [ "${SIZE}" -gt 7500000000 ] 2>/dev/null; then
        USB_DEV="$dev"
        log "  Found USB device: ${USB_DEV} (${SIZE} bytes)"
        break
    fi
done

if [ -z "$USB_DEV" ]; then
    # Fallback: first real disk (not loop/ram/sr)
    USB_DEV=$(lsblk -ndo NAME,TYPE 2>/dev/null | awk '$2=="disk" {print "/dev/"$1; exit}')
    if [ -z "$USB_DEV" ]; then
        USB_DEV=$(lsblk -ndo NAME 2>/dev/null | grep -v -E '^(loop|ram|sr)' | head -1)
        [ -n "$USB_DEV" ] && USB_DEV="/dev/${USB_DEV}"
    fi
    [ -z "$USB_DEV" ] && USB_DEV="/dev/sda"
    warn "  Could not auto-detect USB. Using: ${USB_DEV}"
fi

# === Stage 4: Create Persistence Partition ===
PERSIST_PART="${USB_DEV}2"
PERSIST_MOUNT="/mnt/persist"

log "Creating persistence partition on ${PERSIST_PART}..."

# WARNING: This will create a new partition. In production, check for existing first.
if [ ! -b "$PERSIST_PART" ]; then
    log "  Partitioning ${USB_DEV}..."
    # Create a DOS label with partition 2 = 6GB persistence (partition 1 = ISO data)
    printf 'label: dos\n,,L\n' | sfdisk "$USB_DEV" > /dev/null 2>&1 || true
    sleep 2
    # If sfdisk made partition 1 only, rename expectation: use p1 as persistence fallback
    if [ ! -b "$PERSIST_PART" ] && [ -b "${USB_DEV}1" ]; then
        PERSIST_PART="${USB_DEV}1"
        log "  Using partition 1 as persistence: ${PERSIST_PART}"
    fi
fi

if [ -b "$PERSIST_PART" ]; then
    log "  Formatting ${PERSIST_PART} as ext4..."
    mkfs.ext4 -F "$PERSIST_PART" > /dev/null 2>&1 || warn "  Format may have failed (partition already formatted?)"
else
    err "  Failed to create persistence partition. Cannot continue."
    err "  Dropping to emergency shell (PID 1 must not exit)..."
    exec /bin/sh
fi

# === Stage 5: Mount Persistence ===
log "Mounting persistence at ${PERSIST_MOUNT}..."
mkdir -p "$PERSIST_MOUNT"
mount "$PERSIST_PART" "$PERSIST_MOUNT" || {
    err "  Failed to mount persistence partition."
    err "  Dropping to emergency shell..."
    exec /bin/sh
}

# === Stage 6: Extract Bootstrap Tarball ===
BOOTSTRAP_TAR="/aios-bootstrap.tar.gz"

if [ -f "$BOOTSTRAP_TAR" ]; then
    log "Extracting AIOS bootstrap to persistence..."
    tar -xzf "$BOOTSTRAP_TAR" -C "$PERSIST_MOUNT" || {
        err "  Failed to extract bootstrap. USB image may be corrupted."
        err "  Dropping to emergency shell..."
        exec /bin/sh
    }
else
    err "  Bootstrap tarball not found at ${BOOTSTRAP_TAR}."
    err "  The USB image is incomplete. Please reflash."
    err "  Dropping to emergency shell..."
    exec /bin/sh
fi

# === Stage 7: Write Runtime Config ===
CONFIG_FILE="${PERSIST_MOUNT}/etc/aios.conf"
mkdir -p "$(dirname "$CONFIG_FILE")"

cat > "$CONFIG_FILE" << EOF
# AIOS Runtime Configuration — auto-generated by first_boot.sh
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

HARDWARE_RAM_MB=${TOTAL_RAM}
HARDWARE_CPU_CORES=${CPU_CORES}
HARDWARE_CPU_MODEL="${CPU_MODEL}"

MODEL_PRIMARY=${MODEL}
MODEL_REVIEWER=${REVIEWER_MODEL}
MODEL_VALIDATOR=${VALIDATOR_MODEL}

BOOTSTRAP_VERSION=0.1.0-p0
FIRST_BOOT_COMPLETE=true
EOF

log "Runtime config written to ${CONFIG_FILE}"

# === Stage 8: Launch Orchestrator ===
log "========================================="
log "Bootstrap complete. Launching AIOS orchestrator..."
log ""

# Switch to persistence and launch
exec chroot "$PERSIST_MOUNT" /aios/launch.sh || {
    err "Failed to launch orchestrator."
    err "Dropping to emergency shell..."
    exec /bin/sh
}
