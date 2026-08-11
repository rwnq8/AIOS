#!/bin/bash
# AIOS Alpine ISO Builder v0.1.1-p0
# Builds a bootable Alpine Linux ISO with embedded AIOS bootstrap tarball.

set -e

OUTPUT="${OUTPUT_DIR:-/output}"
VERSION="0.1.0-p0"
ISO_NAME="aios-v${VERSION}"
WORK="/build/work"
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine/v3.21"

echo "=========================================="
echo " AIOS ISO BUILDER v${VERSION}"
echo "=========================================="
echo ""

# === Stage 1: Download Alpine base ===
echo "[1/6] Downloading Alpine base packages..."
mkdir -p "${WORK}/apks"

# Core packages for bootable USB
PACKAGES=(
    alpine-base
    alpine-mkinitfs
    busybox
    busybox-openrc
    openrc
    e2fsprogs
    e2fsprogs-extra
    blkid
    lsblk
    util-linux
    util-linux-misc
    sfdisk
    dosfstools
    grub
    grub-bios
    grub-efi
    linux-lts
    mkinitfs
    openssh
    bash
    curl
    ca-certificates
    python3
    py3-pip
    gcc
    make
    git
    musl-dev
    cmake
)

echo "  Packages: ${#PACKAGES[@]}"

# Download all packages
for pkg in "${PACKAGES[@]}"; do
    apk fetch --repositories-file /etc/apk/repositories --no-cache -o "${WORK}/apks/" "$pkg" 2>/dev/null || true
done

# === Stage 2: Create rootfs ===
echo "[2/6] Creating root filesystem..."
mkdir -p "${WORK}/rootfs"
ROOTFS="${WORK}/rootfs"

# Configure apk INSIDE the rootfs (required for --root installs)
mkdir -p "${ROOTFS}/etc/apk/keys"
cp -r /etc/apk/keys/* "${ROOTFS}/etc/apk/keys/" 2>/dev/null || true
cat > "${ROOTFS}/etc/apk/repositories" << 'REPOEOF'
https://dl-cdn.alpinelinux.org/alpine/v3.21/main
https://dl-cdn.alpinelinux.org/alpine/v3.21/community
REPOEOF

# Install all packages into rootfs (NO silent failure — errors visible)
apk add --root "${ROOTFS}" --initdb --no-cache "${PACKAGES[@]}"
echo "  Rootfs packages installed: $(apk --root ${ROOTFS} info 2>/dev/null | wc -l)" 

# Configure rootfs
echo "  Configuring rootfs..."

# Set hostname
echo "aios" > "${ROOTFS}/etc/hostname"

# Enable networking on boot
if [ -f "${ROOTFS}/etc/network/interfaces" ]; then
    cat > "${ROOTFS}/etc/network/interfaces" << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
fi

# Configure init
cat > "${ROOTFS}/etc/inittab" << 'EOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
tty1::respawn:/sbin/getty 38400 tty1
tty2::respawn:/sbin/getty 38400 tty2
EOF

# === Stage 3: Embed AIOS bootstrap ===
echo "[3/6] Embedding AIOS bootstrap tarball..."

BOOTSTRAP_TAR="/build/aios-bootstrap.tar.gz"
if [ ! -f "${BOOTSTRAP_TAR}" ]; then
    echo "  WARNING: aios-bootstrap.tar.gz not found at ${BOOTSTRAP_TAR}"
    echo "  Creating empty placeholder..."
    mkdir -p /tmp/aios-empty
    tar -czf "${BOOTSTRAP_TAR}" -C /tmp/aios-empty .
fi

BS_SIZE=$(du -h "${BOOTSTRAP_TAR}" | cut -f1)
echo "  Bootstrap size: ${BS_SIZE}"

# Place bootstrap in initramfs staging
mkdir -p "${ROOTFS}/boot"
cp "${BOOTSTRAP_TAR}" "${ROOTFS}/aios-bootstrap.tar.gz"

# Copy first_boot.sh to initramfs scripts
if [ -d "/build/aios" ]; then
    mkdir -p "${ROOTFS}/sbin"
    cp /build/aios/first_boot.sh "${ROOTFS}/sbin/first_boot.sh" 2>/dev/null || true
    chmod +x "${ROOTFS}/sbin/first_boot.sh" 2>/dev/null || true
fi

# === Stage 4: Configure initramfs ===
echo "[4/6] Configuring initramfs..."

# Create initramfs init script
cat > "${ROOTFS}/init" << 'INITEOF'
#!/bin/sh
# AIOS Initramfs Init v0.1.0-p0
# This runs as PID 1 during early boot

echo "[AIOS] Initramfs starting..."

# Mount basic filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs dev /dev

echo "[AIOS] Hardware detection starting..."

# Load basic kernel modules
modprobe usb-storage 2>/dev/null || true
modprobe sd_mod 2>/dev/null || true
modprobe ext4 2>/dev/null || true

# Find and mount the USB boot device
echo "[AIOS] Searching for AIOS bootstrap..."
sleep 2

# Try to find the bootstrap tarball on the boot medium
BOOTSTRAP="/aios-bootstrap.tar.gz"
for dev in /dev/sd*; do
    if [ -b "$dev" ]; then
        mkdir -p /mnt/boot
        mount "$dev" /mnt/boot 2>/dev/null || continue
        if [ -f "/mnt/boot/aios-bootstrap.tar.gz" ]; then
            BOOTSTRAP="/mnt/boot/aios-bootstrap.tar.gz"
            echo "[AIOS] Found bootstrap on ${dev}"
            break
        fi
        umount /mnt/boot 2>/dev/null
    fi
done

if [ ! -f "${BOOTSTRAP}" ]; then
    echo "[AIOS] FATAL: Bootstrap tarball not found."
    echo "[AIOS] Dropping to emergency shell..."
    exec /bin/sh
fi

echo "[AIOS] Extracting bootstrap..."
mkdir -p /mnt/persist
tar -xzf "${BOOTSTRAP}" -C /mnt/persist

# Run first_boot.sh if available
if [ -f "/mnt/persist/aios/first_boot.sh" ]; then
    echo "[AIOS] Executing first_boot.sh..."
    exec /bin/sh /mnt/persist/aios/first_boot.sh
fi

echo "[AIOS] No first_boot.sh found. Dropping to shell..."
exec /bin/sh
INITEOF

chmod +x "${ROOTFS}/init"

# Create minimal fstab
cat > "${ROOTFS}/etc/fstab" << 'EOF'
proc    /proc    proc    defaults    0 0
sysfs   /sys     sysfs   defaults    0 0
devtmpfs /dev    devtmpfs defaults   0 0
EOF

# === Stage 5: Build squashfs ===
echo "[5/6] Building squashfs image..."

SQUASHFS="${WORK}/aios.squashfs"
mksquashfs "${ROOTFS}" "${SQUASHFS}" -comp xz -b 256K -noappend
SQUASHFS_SIZE=$(du -h "${SQUASHFS}" | cut -f1)
echo "  SquashFS size: ${SQUASHFS_SIZE}"

# === Stage 6: Build ISO ===
echo "[6/6] Building ISO..."

mkdir -p "${WORK}/iso"

# Copy kernel (from rootfs linux-lts package)
mkdir -p "${WORK}/iso"
if [ -f "${ROOTFS}/boot/vmlinuz-lts" ]; then
    cp "${ROOTFS}/boot/vmlinuz-lts" "${WORK}/iso/vmlinuz"
    echo "  Kernel: ${ROOTFS}/boot/vmlinuz-lts"
else
    echo "  WARNING: vmlinuz-lts not found in rootfs — kernel may be missing!"
    ls "${ROOTFS}/boot/" 2>/dev/null || true
fi

# Copy squashfs
cp "${SQUASHFS}" "${WORK}/iso/aios.squashfs"
mkdir -p "${WORK}/iso/boot"
cp "${WORK}/iso/vmlinuz" "${WORK}/iso/boot/vmlinuz" 2>/dev/null || true
cp "${WORK}/iso/aios.squashfs" "${WORK}/iso/boot/aios.squashfs" 2>/dev/null || true

# Create isolinux config
mkdir -p "${WORK}/iso/isolinux"
cat > "${WORK}/iso/isolinux/isolinux.cfg" << 'EOF'
DEFAULT aios
LABEL aios
    KERNEL /vmlinuz
    APPEND root=/dev/ram0 init=/init console=tty1 quiet loglevel=3
    INITRD /aios.squashfs
TIMEOUT 50
PROMPT 1
EOF

# Copy isolinux binaries
if [ -f /usr/share/syslinux/isolinux.bin ]; then
    cp /usr/share/syslinux/isolinux.bin "${WORK}/iso/isolinux/"
fi
if [ -f /usr/share/syslinux/ldlinux.c32 ]; then
    cp /usr/share/syslinux/ldlinux.c32 "${WORK}/iso/isolinux/"
fi

# Build the ISO
OUTPUT_ISO="${OUTPUT}/${ISO_NAME}.iso"
mkdir -p "${OUTPUT}"

xorriso -as mkisofs \
    -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e isolinux/efiboot.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "${OUTPUT_ISO}" \
    "${WORK}/iso" 2>&1 || {
    echo "  xorriso failed, trying genisoimage..."
    genisoimage -o "${OUTPUT_ISO}" \
        -b isolinux/isolinux.bin -c isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        "${WORK}/iso" 2>&1 || true
}

if [ -f "${OUTPUT_ISO}" ]; then
    ISO_SIZE=$(du -h "${OUTPUT_ISO}" | cut -f1)
    echo ""
    echo "=========================================="
    echo " ISO BUILD SUCCESSFUL"
    echo "=========================================="
    echo "  Output:  ${OUTPUT_ISO}"
    echo "  Size:    ${ISO_SIZE}"
    echo "  Version: v${VERSION}"
    echo ""
    echo "  Write to USB: dd if=${ISO_NAME}.iso of=/dev/sdX bs=4M status=progress"
    echo "=========================================="
else
    echo ""
    echo "=========================================="
    echo " ISO BUILD FAILED"
    echo "=========================================="
    echo "  Check the errors above. Common issues:"
    echo "  - Missing isolinux binaries"
    echo "  - Missing kernel (vmlinuz-lts)"
    echo "=========================================="
    exit 1
fi
