#!/bin/bash
# Run this script inside Uncode terminal to apply all latest fixes locally

echo "=== Uncode APT Hook Fix Script ==="
echo ""

# Fix 1: pre-install-rewrite.sh (directory rename fix)
echo "[1/3] Fixing pre-install hook (directory rename)..."
cat << 'EOF' > $PREFIX/etc/apt/uncode-pre-install-rewrite.sh
#!/data/data/com.uncode/files/usr/bin/bash
# Pre-install rewrite: patch .deb maintainer scripts before dpkg extracts them
PREFIX=/data/data/com.uncode/files/usr
OLD_PKG=com.termux
NEW_PKG=com.uncode
TMPWORK="${PREFIX}/tmp/.uncode-deb-rewrite"

while IFS= read -r line; do
    deb_path=$(echo "$line" | awk '{print $1}')
    [ -z "$deb_path" ] && continue
    [ ! -f "$deb_path" ] && continue
    [[ "$deb_path" != *.deb ]] && continue

    WORK="${TMPWORK}/$(basename "$deb_path" .deb)"
    rm -rf "$WORK"
    mkdir -p "$WORK"

    # Extract, rewrite all text files, rebuild
    dpkg-deb -R "$deb_path" "$WORK" 2>/dev/null || continue
    
    matches=$(grep -rlI "/data/data/${OLD_PKG}/" "$WORK" 2>/dev/null)
    if [ -n "$matches" ]; then
        printf '%s\n' "$matches" | while IFS= read -r f; do
            sed -i "s|/data/data/${OLD_PKG}/|/data/data/${NEW_PKG}/|g" "$f" 2>/dev/null || true
        done
    fi
    
    # Rename the root directory structure inside the .deb
    if [ -d "$WORK/data/data/${OLD_PKG}" ]; then
        mv "$WORK/data/data/${OLD_PKG}" "$WORK/data/data/${NEW_PKG}"
    fi

    for s in preinst postinst prerm postrm; do
        [ -f "$WORK/DEBIAN/$s" ] && chmod 0755 "$WORK/DEBIAN/$s" 2>/dev/null
    done
    dpkg-deb -b "$WORK" "$deb_path" >/dev/null 2>&1 || true
    
    rm -rf "$WORK"
done

rm -rf "$TMPWORK"
EOF
chmod +x $PREFIX/etc/apt/uncode-pre-install-rewrite.sh
echo "    Done."

# Fix 2: patchelf hook (timing fix)
echo "[2/3] Fixing patchelf hook (timing bug)..."
cat << 'EOF' > $PREFIX/etc/apt/uncode-patchelf-hook.sh
#!/data/data/com.uncode/files/usr/bin/bash
# Patchelf hook: byte-patch com.termux→com.uncode in recently installed ELF binaries
PREFIX=/data/data/com.uncode/files/usr
OLD_ID=com.termux
NEW_ID=com.uncode
MARKER="$PREFIX/tmp/.uncode-last-install"

# Find ELF files modified since last run (or in the last 10 minutes if no marker)
if [ -f "$MARKER" ]; then
    find "$PREFIX/bin" "$PREFIX/lib" "$PREFIX/libexec" -type f -newer "$MARKER" -print0 2>/dev/null | while IFS= read -r -d '' file; do
        head -c4 "$file" 2>/dev/null | grep -q $'\x7fELF' || continue
        perl -pi -e "s|/data/data/$OLD_ID/|/data/data/$NEW_ID/|g" "$file" 2>/dev/null || true
    done
else
    # No marker yet — patch all ELF files modified in last 10 minutes
    find "$PREFIX/bin" "$PREFIX/lib" "$PREFIX/libexec" -type f -mmin -10 -print0 2>/dev/null | while IFS= read -r -d '' file; do
        head -c4 "$file" 2>/dev/null | grep -q $'\x7fELF' || continue
        perl -pi -e "s|/data/data/$OLD_ID/|/data/data/$NEW_ID/|g" "$file" 2>/dev/null || true
    done
fi

# Update marker AFTER patching
touch "$MARKER"
EOF
chmod +x $PREFIX/etc/apt/uncode-patchelf-hook.sh
echo "    Done."

# Fix 3: Patch already-installed broken binaries (node, htop, etc.)
echo "[3/3] Patching already-installed ELF binaries with wrong RUNPATH..."
for f in $(find $PREFIX/bin $PREFIX/lib $PREFIX/libexec -type f 2>/dev/null); do
    head -c4 "$f" 2>/dev/null | grep -q $'\x7fELF' || continue
    grep -q "com.termux" "$f" 2>/dev/null || continue
    perl -pi -e 's|/data/data/com\.termux/|/data/data/com.uncode/|g' "$f" 2>/dev/null
    echo "    Patched: $f"
done
echo "    Done."

echo ""
echo "=== All fixes applied! ==="
echo "Try: node -v && htop --version"
