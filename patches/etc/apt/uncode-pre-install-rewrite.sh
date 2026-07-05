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
