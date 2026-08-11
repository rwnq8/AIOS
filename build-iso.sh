#!/bin/bash
# AIOS Alpine ISO Builder v0.1.1-p0
# Bootable Alpine Linux ISO with embedded AIOS bootstrap tarball.
# Boot model: small cpio initramfs (/init) mounts aios.squashfs via loop,
# then switch_root into the Alpine rootfs which runs /sbin/first_boot.sh.
# Hybrid UEFI (grub-mkstandalone efiboot.img) + BIOS (isolinux).

set -e

OUTPUT="${OUTPUT_DIR:-/output}"
VERSION="0.1.3-p0"
ISO_NAME="aios-v${VERSION}"
WORK="/build/work"
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine/v3.21"

echo "=========================================="
echo " AIOS ISO BUILDER v${VERSION}"
echo "=========================================="
echo ""

# === Stage 1: Package list ===
PACKAGES=(
    alpine-base
    busybox
    busybox-openrc
    busybox-static
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
echo "[1/6] Package list: ${#PACKAGES[@]} packages"

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
echo "aios" > "${ROOTFS}/etc/hostname"

if [ -f "${ROOTFS}/etc/network/interfaces" ]; then
    cat > "${ROOTFS}/etc/network/interfaces" << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
fi

cat > "${ROOTFS}/etc/inittab" << 'EOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
tty1::respawn:/sbin/getty 38400 tty1
ttyS0::respawn:/sbin/getty 38400 ttyS0
EOF

cat > "${ROOTFS}/etc/fstab" << 'EOF'
proc    /proc    proc    defaults    0 0
sysfs   /sys     sysfs   defaults    0 0
devtmpfs /dev    devtmpfs defaults   0 0
EOF

# === Stage 3: Embed AIOS bootstrap ===
echo "[3/6] Embedding AIOS bootstrap tarball..."
BOOTSTRAP_TAR="/build/aios-bootstrap.tar.gz"
if [ ! -f "${BOOTSTRAP_TAR}" ]; then
    echo "  WARNING: aios-bootstrap.tar.gz not found — creating empty placeholder"
    mkdir -p /tmp/aios-empty
    tar -czf "${BOOTSTRAP_TAR}" -C /tmp/aios-empty .
fi
BS_SIZE=$(du -h "${BOOTSTRAP_TAR}" | cut -f1)
echo "  Bootstrap size: ${BS_SIZE}"
cp "${BOOTSTRAP_TAR}" "${ROOTFS}/aios-bootstrap.tar.gz"

# Copy AIOS scripts into the rootfs
if [ -d "/build/aios" ]; then
    mkdir -p "${ROOTFS}/sbin" "${ROOTFS}/aios"
    cp /build/aios/first_boot.sh "${ROOTFS}/sbin/first_boot.sh" 2>/dev/null || true
    chmod +x "${ROOTFS}/sbin/first_boot.sh" 2>/dev/null || true
    cp /build/aios/orchestrator.py "${ROOTFS}/aios/orchestrator.py" 2>/dev/null || true
    cp /build/aios/launch.sh "${ROOTFS}/aios/launch.sh" 2>/dev/null || true
    chmod +x "${ROOTFS}/aios/launch.sh" 2>/dev/null || true
fi

# === Stage 4: Build cpio initramfs ===
echo "[4/6] Building initramfs (cpio)..."
mkdir -p "${WORK}/initramfs"

# Static busybox for the initramfs (no dependencies)
BB_STATIC=""
for cand in "${ROOTFS}/bin/busybox.static" /bin/busybox.static /usr/bin/busybox.static; do
    if [ -f "$cand" ]; then
        BB_STATIC="$cand"
        break
    fi
done
if [ -z "$BB_STATIC" ]; then
    echo "  FATAL: busybox.static not found"
    exit 1
fi
mkdir -p "${WORK}/initramfs/bin"
cp "$BB_STATIC" "${WORK}/initramfs/bin/busybox"
chmod +x "${WORK}/initramfs/bin/busybox"
echo "  busybox.static: $BB_STATIC"

cat > "${WORK}/initramfs/init" << 'INITEOF'
#!/bin/busybox sh
# AIOS initramfs /init v0.1.3-p0 — runs as PID 1
BB=/bin/busybox
echo "[AIOS] initramfs starting..."
$BB mkdir -p /proc /sys /dev /cdrom /squash
$BB mount -t proc proc /proc
$BB mount -t sysfs sysfs /sys
$BB mount -t devtmpfs dev /dev
$BB sleep 1

# Load loop + squashfs modules if modular
$BB modprobe loop 2>/dev/null || true
$BB modprobe squashfs 2>/dev/null || true

found=0
for dev in sr0 sr1 sda sdb sdc sdd hda hdb; do
    [ -b "/dev/$dev" ] || continue
    if $BB mount -t iso9660 -o ro "/dev/$dev" /cdrom 2>/dev/null; then
        if [ -f /cdrom/aios.squashfs ]; then
            echo "[AIOS] Boot medium found: /dev/$dev (ISO)"
            found=1
            break
        fi
        $BB umount /cdrom 2>/dev/null
    fi
done

if [ $found -eq 0 ]; then
    echo "[AIOS] FATAL: no boot medium with aios.squashfs found"
    echo "[AIOS] Dropping to emergency shell"
    exec $BB sh
fi

echo "[AIOS] Mounting squashfs root..."
$BB mount -t squashfs -o loop,ro /cdrom/aios.squashfs /squash || {
    echo "[AIOS] FATAL: squashfs mount failed"
    exec $BB sh
}

echo "[AIOS] Pivoting to squashfs root..."
$BB mount --move /dev /squash/dev
$BB mount --move /proc /squash/proc
$BB mount --move /sys /squash/sys

echo "[AIOS] switch_root -> /sbin/first_boot.sh"
exec $BB switch_root /squash /sbin/first_boot.sh
INITEOF
chmod +x "${WORK}/initramfs/init"

# Build the cpio archive
cd "${WORK}/initramfs"
find . | cpio -o -H newc 2>/dev/null | gzip > "${WORK}/initramfs.img"
INITRAMFS_SIZE=$(du -h "${WORK}/initramfs.img" | cut -f1)
echo "  initramfs.img: ${INITRAMFS_SIZE}"

# === Stage 5: Build squashfs ===
echo "[5/6] Building squashfs image..."
SQUASHFS="${WORK}/aios.squashfs"
mksquashfs "${ROOTFS}" "${SQUASHFS}" -comp xz -b 256K -noappend
SQUASHFS_SIZE=$(du -h "${SQUASHFS}" | cut -f1)
echo "  SquashFS size: ${SQUASHFS_SIZE}"

# === Stage 6: Build ISO ===
echo "[6/6] Building ISO..."
ISO_DIR="${WORK}/iso"
mkdir -p "${ISO_DIR}/boot" "${ISO_DIR}/isolinux"

# Kernel
if [ -f "${ROOTFS}/boot/vmlinuz-lts" ]; then
    cp "${ROOTFS}/boot/vmlinuz-lts" "${ISO_DIR}/boot/vmlinuz"
    echo "  Kernel: vmlinuz-lts"
else
    echo "  FATAL: vmlinuz-lts not found in rootfs"
    exit 1
fi

# Initramfs + squashfs
cp "${WORK}/initramfs.img" "${ISO_DIR}/boot/initramfs.img"
cp "${SQUASHFS}" "${ISO_DIR}/aios.squashfs"

# ISOLINUX (BIOS) config
cat > "${ISO_DIR}/isolinux/isolinux.cfg" << 'EOF'
DEFAULT aios
LABEL aios
    KERNEL /boot/vmlinuz
    INITRD /boot/initramfs.img
    APPEND console=tty1 console=ttyS0,115200 quiet loglevel=3
TIMEOUT 50
PROMPT 1
EOF

# Copy isolinux binaries
if [ -f /usr/share/syslinux/isolinux.bin ]; then
    cp /usr/share/syslinux/isolinux.bin "${ISO_DIR}/isolinux/"
fi
if [ -f /usr/share/syslinux/ldlinux.c32 ]; then
    cp /usr/share/syslinux/ldlinux.c32 "${ISO_DIR}/isolinux/"
fi

# UEFI boot image via grub-mkstandalone
if command -v grub-mkstandalone > /dev/null 2>&1; then
    echo "  Building UEFI boot image..."
    cat > "${WORK}/grub-efi.cfg" << 'GRUBEOF'
set timeout=5
set default=0
menuentry "AIOS v0.1.3-p0" {
    linux /boot/vmlinuz console=tty1 console=ttyS0,115200 quiet loglevel=3
    initrd /boot/initramfs.img
}
GRUBEOF
    grub-mkstandalone -O x86_64-efi -o "${ISO_DIR}/isolinux/efiboot.img" \
        --modules="normal linux iso9660 squash4 loopback part_msdos part_gpt fat search configfile" \
        --themes='' --locales='' \
        -d /usr/lib/grub/x86_64-efi \
        "boot/grub/grub.cfg=${WORK}/grub-efi.cfg" 2>&1 | tail -3 || echo "  WARNING: grub-mkstandalone failed"
    ls -la "${ISO_DIR}/isolinux/efiboot.img" 2>/dev/null || echo "  WARNING: efiboot.img not created"
else
    echo "  WARNING: grub-mkstandalone not found — BIOS-only ISO"
fi

# Assemble ISO
OUTPUT_ISO="${OUTPUT}/${ISO_NAME}.iso"
mkdir -p "${OUTPUT}"

if [ -f "${ISO_DIR}/isolinux/efiboot.img" ]; then
    XORRISO_CMD="xorriso -as mkisofs \
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
    -o \"${OUTPUT_ISO}\" \
    \"${ISO_DIR}\""
else
    XORRISO_CMD="xorriso -as mkisofs \
    -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -o \"${OUTPUT_ISO}\" \
    \"${ISO_DIR}\""
fi

echo "  Running: ${XORRISO_CMD}"
eval "${XORRISO_CMD}" 2>&1 || {
    echo "  ISO assembly failed"
    exit 1
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
    exit 1
fi
