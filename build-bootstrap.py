#!/usr/bin/env python3
"""
AIOS Bootstrap Builder — v0.1.0-p0
Downloads GGUF models and packages them into aios-bootstrap.tar.gz
for embedding in the Alpine Linux initramfs.

Usage:
    python build-bootstrap.py              # Download all models + build tarball
    python build-bootstrap.py --dry-run    # Show what would be downloaded
    python build-bootstrap.py --model-only # Download only, skip tarball
"""

import urllib.request
import json
import os
import sys
import hashlib
import shutil
import tarfile
import time
import argparse

# === Configuration ===
MODELS = {
    "primary": {
        "name": "DeepSeek-Coder 1.3B Instruct",
        "url": "https://huggingface.co/TheBloke/deepseek-coder-1.3b-instruct-GGUF/resolve/main/deepseek-coder-1.3b-instruct.Q4_K_M.gguf",
        "dest": "models/deepseek-coder-1.3b-instruct.Q4_K_M.gguf",
        "min_ram_mb": 4096,
    },
    "reviewer": {
        "name": "Granite 3.2 2B Instruct",
        "url": "https://huggingface.co/ibm-research/granite-3.2-2b-instruct-GGUF/resolve/main/granite-3.2-2b-instruct.Q4_K_M.gguf",
        "dest": "models/granite-3.2-2b-instruct.Q4_K_M.gguf",
        "min_ram_mb": 8192,
    },
    "validator": {
        "name": "Gemma 3 1B Instruct",
        "url": "https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf",
        "dest": "models/gemma-3-1b-it.Q4_K_M.gguf",
        "min_ram_mb": 4096,
    },
}

BOOTSTRAP_FILES = [
    "aios/first_boot.sh",
    "aios/orchestrator.py",
    "aios/launch.sh",
    "etc/aios.conf",
    "checksums.sha256",
    "MANIFEST.txt",
]


def download_file(url, dest, label=""):
    """Download a file with progress reporting."""
    dest_tmp = dest + ".tmp"

    if os.path.exists(dest):
        size_mb = os.path.getsize(dest) / 1e6
        print(f"  [{label}] Already downloaded ({size_mb:.0f} MB)")
        return True

    print(f"  [{label}] Downloading...")
    t0 = time.time()

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "AIOS-bootstrap/1.0"})
        with urllib.request.urlopen(req) as resp:
            total = int(resp.headers.get("Content-Length", 0))
            downloaded = 0
            last_report = 0
            with open(dest_tmp, "wb") as f:
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total > 0 and time.time() - last_report > 2:
                        pct = downloaded / total * 100
                        elapsed = time.time() - t0
                        speed = (downloaded / 1e6) / elapsed if elapsed > 0 else 0
                        eta = (total - downloaded) / (speed * 1e6) if speed > 0 else 0
                        print(f"    {pct:.0f}%  {downloaded/1e6:.0f}/{total/1e6:.0f} MB  "
                              f"{speed:.1f} MB/s  ETA {eta:.0f}s", end="\r")
                        last_report = time.time()

        os.rename(dest_tmp, dest)
        elapsed = time.time() - t0
        actual_mb = os.path.getsize(dest) / 1e6
        speed = actual_mb / elapsed if elapsed > 0 else 0
        print(f"\n    Done: {actual_mb:.0f} MB in {elapsed:.0f}s ({speed:.1f} MB/s)")
        return True
    except Exception as e:
        print(f"\n    ERROR: {e}")
        if os.path.exists(dest_tmp):
            os.remove(dest_tmp)
        return False


def compute_checksums(bootstrap_dir):
    """Compute SHA256 for all model files."""
    checksums = {}
    models_dir = os.path.join(bootstrap_dir, "models")
    if not os.path.exists(models_dir):
        return checksums

    for fname in os.listdir(models_dir):
        fpath = os.path.join(models_dir, fname)
        if not fname.endswith(".gguf"):
            continue
        sha = hashlib.sha256()
        with open(fpath, "rb") as f:
            while True:
                chunk = f.read(65536)
                if not chunk:
                    break
                sha.update(chunk)
        checksums[f"models/{fname}"] = sha.hexdigest()
    return checksums


def build_manifest(bootstrap_dir, checksums):
    """Write MANIFEST.txt."""
    manifest_path = os.path.join(bootstrap_dir, "MANIFEST.txt")
    total_size = sum(
        os.path.getsize(os.path.join(root, f))
        for root, _, files in os.walk(bootstrap_dir)
        for f in files
        if f != "MANIFEST.txt"
    )

    with open(manifest_path, "w") as f:
        f.write(f"AIOS Bootstrap v0.1.0-p0\n")
        f.write(f"Build date: {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\n")
        f.write(f"Total size: {total_size / 1e6:.0f} MB\n\n")
        f.write("Models:\n")
        for dest_path, sha in sorted(checksums.items()):
            fpath = os.path.join(bootstrap_dir, dest_path)
            if os.path.exists(fpath):
                size = os.path.getsize(fpath) / 1e6
                f.write(f"  {dest_path} ({size:.0f} MB, SHA256: {sha[:16]}...)\n")
        f.write("\nFiles:\n")
        for root, _, files in sorted(os.walk(bootstrap_dir)):
            for fname in sorted(files):
                if fname in ("MANIFEST.txt",):
                    continue
                fpath = os.path.join(root, fname)
                rel = os.path.relpath(fpath, bootstrap_dir).replace("\\", "/")
                size = os.path.getsize(fpath)
                f.write(f"  {rel} ({size} bytes)\n")


def main():
    parser = argparse.ArgumentParser(description="AIOS Bootstrap Builder")
    parser.add_argument("--dry-run", action="store_true", help="Show plan, don't download")
    parser.add_argument("--model-only", action="store_true", help="Download models only, skip tarball")
    args = parser.parse_args()

    # Use temp dir for build
    temp = os.environ.get("TEMP", "/tmp")
    build_dir = os.path.join(temp, "aios-bootstrap")
    models_dir = os.path.join(build_dir, "models")

    print("=" * 60)
    print("AIOS BOOTSTRAP BUILDER v0.1.0-p0")
    print("=" * 60)
    print()

    # === Estimate ===
    total_est = sum(1 for m in MODELS.values())  # rough
    print(f"Models to download: {len(MODELS)}")
    print(f"Build directory: {build_dir}")
    print()

    if args.dry_run:
        for role, info in MODELS.items():
            print(f"  [{role}] {info['name']}")
            print(f"         URL: {info['url']}")
            print(f"         Min RAM: {info['min_ram_mb']} MB")
        return

    # === Create directories ===
    for d in [models_dir, os.path.join(build_dir, "aios"), os.path.join(build_dir, "etc")]:
        os.makedirs(d, exist_ok=True)

    # === Download models ===
    print("--- Downloading Models ---")
    for role, info in MODELS.items():
        dest = os.path.join(build_dir, info["dest"])
        download_file(info["url"], dest, f"{role} ({info['name']})")

    # === Compute checksums ===
    print("\n--- Computing Checksums ---")
    checksums = compute_checksums(build_dir)
    checksum_path = os.path.join(build_dir, "checksums.sha256")
    with open(checksum_path, "w") as f:
        for path, sha in sorted(checksums.items()):
            print(f"  {sha[:16]}...  {path}")
            f.write(f"{sha}  {path}\n")

    # === Copy scripts (from repo) ===
    print("\n--- Copying Scripts ---")
    repo_dir = os.path.dirname(os.path.abspath(__file__))
    for script in ["first_boot.sh", "orchestrator.py", "launch.sh"]:
        src = os.path.join(repo_dir, script)
        dst = os.path.join(build_dir, "aios", script)
        if os.path.exists(src):
            shutil.copy2(src, dst)
            print(f"  {script} -> aios/")
        else:
            print(f"  WARNING: {script} not found (running standalone?)")

    # Write etc/aios.conf placeholder
    with open(os.path.join(build_dir, "etc", "aios.conf"), "w") as f:
        f.write("# AIOS Runtime Configuration — placeholder, filled by first_boot.sh\n")
        f.write("BOOTSTRAP_VERSION=0.1.0-p0\n")

    # === Build manifest ===
    print("\n--- Building Manifest ---")
    build_manifest(build_dir, checksums)

    if args.model_only:
        print("\n=== MODELS DOWNLOADED (--model-only) ===")
        return

    # === Create tarball ===
    print("\n--- Creating Tarball ---")
    tarball_path = os.path.join(temp, "aios-bootstrap.tar.gz")
    with tarfile.open(tarball_path, "w:gz") as tar:
        tar.add(build_dir, arcname=".")
    tarball_mb = os.path.getsize(tarball_path) / 1e6
    print(f"  {tarball_path}")
    print(f"  Size: {tarball_mb:.0f} MB")

    # === Summary ===
    print()
    print("=" * 60)
    print("BUILD COMPLETE")
    print("=" * 60)
    print(f"  Tarball: {tarball_path}")
    print(f"  Models:  {len(checksums)}")
    print(f"  Size:    {tarball_mb:.0f} MB")
    print()
    print("Next: Build the ISO with Docker")
    print("  docker build -t aios-builder .")
    print("  docker run --rm -v $(pwd)/output:/output aios-builder")


if __name__ == "__main__":
    main()
