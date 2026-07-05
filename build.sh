#!/usr/bin/env bash
set -euo pipefail

# ── uncode-bootstrap build script ─────────────────────────────────────────
# Rewrites a vanilla Termux bootstrap zip (com.termux) into one that uses
# the com.uncode package prefix.  Because both names are exactly 10 bytes
# the byte-level patching of ELF files is offset-safe.
# Usage: ./build.sh <input.zip> <output.zip>
# ──────────────────────────────────────────────────────────────────────────

OLD_PKG="com.termux"
NEW_PKG="com.uncode"
OLD_PREFIX="/data/data/${OLD_PKG}/"
NEW_PREFIX="/data/data/${NEW_PKG}/"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── argument handling ─────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <input zip> <output zip>"
    exit 1
fi

IN_ZIP="$(realpath "$1")"
OUT_ZIP="$(realpath -m "$2")"

if [[ ! -f "$IN_ZIP" ]]; then
    echo "ERROR: Input zip not found: $IN_ZIP"
    exit 1
fi

# ── temp work dir with cleanup ────────────────────────────────────────────

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/uncode-bootstrap.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

ROOTFS="$WORKDIR/rootfs"
mkdir -p "$ROOTFS"

echo "═══════════════════════════════════════════════════════════"
echo "  uncode-bootstrap builder"
echo "  Input:  $IN_ZIP"
echo "  Output: $OUT_ZIP"
echo "═══════════════════════════════════════════════════════════"

# ── step 1: extract ──────────────────────────────────────────────────────

echo ""
echo "→ Extracting vanilla bootstrap..."
unzip -q -o "$IN_ZIP" -d "$ROOTFS"
echo "  ✓ Extracted to staging rootfs"

# ── step 2: overlay patches ─────────────────────────────────────────────

echo ""
echo "→ Copying patch overlay..."
if [[ -d "$SCRIPT_DIR/patches" ]]; then
    cp -a "$SCRIPT_DIR/patches/." "$ROOTFS/"
    echo "  ✓ Patches applied"
else
    echo "  ⚠ No patches/ directory found, skipping overlay"
fi

# ── step 3: rewrite dpkg metadata ───────────────────────────────────────

echo ""
echo "→ Rewriting dpkg metadata (${OLD_PREFIX} → ${NEW_PREFIX})..."

DPKG_INFO_DIR="$ROOTFS/var/lib/dpkg/info"
DPKG_STATUS="$ROOTFS/var/lib/dpkg/status"

rewrite_count=0

# Rewrite dpkg info files
if [[ -d "$DPKG_INFO_DIR" ]]; then
    for ext in postinst postrm preinst prerm conffiles md5sums list triggers templates; do
        for f in "$DPKG_INFO_DIR"/*."$ext" ; do
            [[ -f "$f" ]] || continue
            if grep -q "$OLD_PREFIX" "$f" 2>/dev/null; then
                sed -i "s|${OLD_PREFIX}|${NEW_PREFIX}|g" "$f"
                rewrite_count=$((rewrite_count + 1))
            fi
        done
    done
fi

echo "  ✓ Rewrote $rewrite_count dpkg info files"

# Rewrite dpkg status database
if [[ -f "$DPKG_STATUS" ]]; then
    if grep -q "$OLD_PREFIX" "$DPKG_STATUS" 2>/dev/null; then
        sed -i "s|${OLD_PREFIX}|${NEW_PREFIX}|g" "$DPKG_STATUS"
        echo "  ✓ Rewrote dpkg status database"
    else
        echo "  · dpkg status: no references to patch"
    fi
else
    echo "  ⚠ dpkg status file not found"
fi

# ── step 3.5: rewrite ELF binaries and scripts ──────────────────────────

echo ""
echo "→ Rewriting ELF binaries and text scripts (${OLD_PREFIX} → ${NEW_PREFIX})..."
find "$ROOTFS/bin" "$ROOTFS/lib" "$ROOTFS/libexec" "$ROOTFS/share" "$ROOTFS/var" "$ROOTFS/etc" -type f \
    ! -name "*.gpg" \
    ! -name "*.tar.*" \
    ! -name "*.zip" \
    ! -name "*.gz" \
    -print0 2>/dev/null | xargs -0 -r perl -pi -e "s|/data/data/${OLD_PKG}/|/data/data/${NEW_PKG}/|g" || true
echo "  ✓ Binaries and scripts patched"

# ── step 3.6: rewrite SYMLINKS.txt ───────────────────────────────────────
# Termux bootstrap ZIPs don't store real symlinks — they store symlink
# definitions in SYMLINKS.txt (format: target←link).  The app recreates
# them at first boot.  We must patch the targets here.

echo ""
echo "→ Rewriting SYMLINKS.txt (${OLD_PREFIX} → ${NEW_PREFIX})..."
if [[ -f "$ROOTFS/SYMLINKS.txt" ]]; then
    sed -i "s|${OLD_PREFIX}|${NEW_PREFIX}|g" "$ROOTFS/SYMLINKS.txt"
    echo "  ✓ SYMLINKS.txt patched"
else
    echo "  ⚠ SYMLINKS.txt not found, skipping"
fi

# ── step 4: re-zip ──────────────────────────────────────────────────────

echo ""
echo "→ Creating output zip..."
mkdir -p "$(dirname "$OUT_ZIP")"
(cd "$ROOTFS" && zip -r -9 --symlinks "$OUT_ZIP" .)
echo "  ✓ Output written to $OUT_ZIP"

# ── summary ──────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════════"
IN_SIZE="$(du -h "$IN_ZIP" | cut -f1)"
OUT_SIZE="$(du -h "$OUT_ZIP" | cut -f1)"
echo "  Input:  $IN_SIZE  ($IN_ZIP)"
echo "  Output: $OUT_SIZE ($OUT_ZIP)"
echo "  dpkg info files rewritten: $rewrite_count"
echo "═══════════════════════════════════════════════════════════"
echo "  Done ✓"
