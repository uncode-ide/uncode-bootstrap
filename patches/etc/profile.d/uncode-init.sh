# Uncode IDE bootstrap init
if [ -z "${TERMUX__PREFIX:-}" ]; then
    export PREFIX=/data/data/com.uncode/files/usr
    export TERMUX__PREFIX="$PREFIX"
    export TERMUX__ROOTFS=/data/data/com.uncode/files
    export HOME=/data/data/com.uncode/files/home
    export TMPDIR="$PREFIX/tmp"
    export LANG=en_US.UTF-8
    export PATH="$PREFIX/bin:$PREFIX/bin/applets:$PATH"
fi
