# AIOS Alpine ISO Builder
# Builds a bootable Alpine Linux ISO with embedded AIOS bootstrap tarball.
#
# Usage:
#   1. Place aios-bootstrap.tar.gz in this directory
#   2. docker build -t aios-builder .
#   3. docker run --rm -v ${PWD}:/output aios-builder
#   4. Output: aios-v0.1.0-p0.iso

FROM alpine:3.21

RUN apk add --no-cache \
    alpine-sdk \
    build-base \
    squashfs-tools \
    syslinux \
    xorriso \
    mtools \
    dosfstools \
    grub \
    grub-bios \
    grub-efi \
    e2fsprogs \
    bash

WORKDIR /build

# Copy build script
COPY build-iso.sh /build/
COPY aios-bootstrap.tar.gz /build/

RUN chmod +x /build/build-iso.sh

ENTRYPOINT ["/build/build-iso.sh"]
