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

    # Extract, rewrite control scripts, rebuild
    dpkg-deb -R "$deb_path" "$WORK" 2>/dev/null || continue
    for script in "$WORK"/DEBIAN/{preinst,postinst,prerm,postrm,conffiles,control}; do
        [ -f "$script" ] && sed -i "s|/data/data/${OLD_PKG}/|/data/data/${NEW_PKG}/|g" "$script" 2>/dev/null || true
    done
    dpkg-deb -b "$WORK" "$deb_path" 2>/dev/null || true
    rm -rf "$WORK"
done

rm -rf "$TMPWORK"
