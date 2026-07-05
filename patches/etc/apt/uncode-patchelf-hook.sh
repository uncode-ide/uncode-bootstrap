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
