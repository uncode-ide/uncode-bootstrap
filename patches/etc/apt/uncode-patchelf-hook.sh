#!/data/data/com.uncode/files/usr/bin/bash
# Patchelf hook: byte-patch com.termux→com.uncode in recently installed ELF binaries
PREFIX=/data/data/com.uncode/files/usr
OLD_ID=com.termux
NEW_ID=com.uncode
MARKER=/tmp/.uncode-last-install

# Create marker if it doesn't exist
[ ! -f "$MARKER" ] && touch -d '1 hour ago' "$MARKER"

# Find recently modified ELF files
find "$PREFIX/bin" "$PREFIX/lib" "$PREFIX/libexec" -type f -newer "$MARKER" -print0 2>/dev/null | while IFS= read -r -d '' file; do
    # Skip non-ELF files
    head -c4 "$file" 2>/dev/null | grep -q $'\x7fELF' || continue
    # Byte-patch (same length = safe)
    perl -pi -e "s|/data/data/$OLD_ID/|/data/data/$NEW_ID/|g" "$file" 2>/dev/null || true
done

# Update marker
touch "$MARKER"
