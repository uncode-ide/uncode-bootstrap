# Uncode Bootstrap Architecture & System Overview

This document provides a deep-dive technical explanation of how **Uncode IDE** (`com.uncode`) utilizes a customized Termux bootstrap userland to allow standard package installation (`apt / pkg install`) from official Termux repositories.

---

## 1. Core Problem & System Architecture

### Problem
- **Termux Package Name:** `com.termux` (Data Path: `/data/data/com.termux/files/usr/...`).
- **Uncode Package Name:** `com.uncode` (Data Path: `/data/data/com.uncode/files/usr/...`).
- Android sandboxing isolates app data directories by package name and UID. `com.uncode` **cannot** read or write to `/data/data/com.termux`.
- Standard `.deb` packages in official Termux repositories contain hardcoded strings pointing to `/data/data/com.termux/` inside:
  1. `DT_RUNPATH` of dynamically linked ELF binaries (`dlopen` library resolution failure).
  2. Script shebang lines (e.g., `#!/data/data/com.termux/files/usr/bin/sh`).
  3. `dpkg` maintainer scripts (`preinst`, `postinst`, `prerm`, `postrm`).
  4. Binary internal string constants and configuration paths.

### Solution
`uncode-bootstrap` enables standard `apt` and `pkg install` operations directly from Termux's official repositories by utilizing a **3-Layer Architecture**.

**Key insight:** `com.termux` and `com.uncode` are both exactly **10 bytes**. The full prefix paths `/data/data/com.termux/` and `/data/data/com.uncode/` are both exactly **22 bytes**. This makes in-place byte substitution inside ELF binaries safe — no offsets shift, no sections need resizing.

---

## 2. Layer-by-Layer Mechanism Breakdown

```
┌───────────────────────────────────────────────────────────────────────────┐
│                    User runs `pkg install <package>`                      │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│ Layer 1: Build-Time Bootstrap Patching (build.sh)                        │
│ Rewrites dpkg metadata, ELF binaries, scripts, and configs               │
│ in the vanilla bootstrap zip from com.termux → com.uncode                │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│ Layer 2: APT Install-Time Hooks                                          │
│ Pre-Install: rewrite .deb text files before dpkg extraction              │
│ Post-Invoke: re-sed dpkg metadata + byte-patch new ELF binaries          │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│ Layer 3: Runtime Environment & Protection                                │
│ Shell init (PREFIX, PATH, HOME) + APT pinning + library protection       │
└───────────────────────────────────────────────────────────────────────────┘
```

---

### Layer 1: Build-Time Bootstrap Patching

**[build.sh](build.sh):**
1. Takes a vanilla `bootstrap-aarch64.zip` (built with default `com.termux` prefix).
2. Extracts it into a staging rootfs.
3. Overlays the static [patches/](patches/) directory.
4. Rewrites dpkg metadata files (`var/lib/dpkg/info/*.{postinst,postrm,...}` and `var/lib/dpkg/status`) using `sed` to replace `/data/data/com.termux/` → `/data/data/com.uncode/`.
5. Byte-patches ALL files in `bin/`, `lib/`, `libexec/`, `share/`, `var/`, `etc/` using `perl -pi -e` to replace `com.termux` → `com.uncode` in both text and binary content. This is offset-safe because both strings are exactly 10 bytes.
6. Rewrites all **symlink targets** that contain `com.termux` paths. This is critical because symlinks (e.g., GPG keyring files in `etc/apt/trusted.gpg.d/` → `share/termux-keyring/`) store their target as filesystem metadata, not file content, so `perl`/`sed` cannot modify them.
7. Re-zips the result with symlink preservation.

---

### Layer 2: APT Install-Time Hooks

APT hooks are registered under [patches/etc/apt/apt.conf.d/](patches/etc/apt/apt.conf.d/):

```
                                  APT Install Lifecycle
                                            │
           ┌────────────────────────────────┴────────────────────────────────┐
           ▼                                                                 ▼
┌───────────────────────────────────────┐                         ┌───────────────────────────────────────┐
│ 97-uncode-pre-install                 │                         │ DPkg::Post-Invoke                     │
│ (DPkg::Pre-Install-Pkgs)              │                         └───────────────────┬───────────────────┘
└──────────────────┬────────────────────┘                                             │
                   │                                                    ┌─────────────┴─────────────┐
                   ▼                                                    ▼                           ▼
┌───────────────────────────────────────┐                ┌──────────────────────┐     ┌──────────────────────┐
│ uncode-pre-install-rewrite.sh         │                │ 99-uncode-rewrite-   │     │ 98-uncode-patchelf   │
│ - Unpacks .deb via dpkg-deb -R       │                │ postinst             │     │ - Finds recently     │
│ - Rewrites shebangs & text files     │                │ - Rewrites dpkg/info │     │   modified ELF files │
│ - Repacks .deb before dpkg runs     │                │   with sed           │     │ - Byte-patches       │
└───────────────────────────────────────┘                └──────────────────────┘     │   com.termux→uncode  │
                                                                                      └──────────────────────┘
```

1. **Pre-Install Hook ([97-uncode-pre-install](patches/etc/apt/apt.conf.d/97-uncode-pre-install) + [uncode-pre-install-rewrite.sh](patches/etc/apt/uncode-pre-install-rewrite.sh)):**
   - Receives list of `.deb` file paths on stdin (APT protocol v1).
   - Unpacks each `.deb` with `dpkg-deb -R`.
   - Uses `grep -rlI` to find all text files containing `/data/data/com.termux/`.
   - Rewrites matches with `sed -i` to `/data/data/com.uncode/`.
   - Fixes DEBIAN script permissions to `0755` and repacks with `dpkg-deb -b`.
   - This ensures all text files (scripts, configs, `.pc` files) in the `.deb` are patched **before** dpkg extracts them.

2. **Post-Unpack Metadata Rewrite ([99-uncode-rewrite-postinst](patches/etc/apt/apt.conf.d/99-uncode-rewrite-postinst)):**
   - Runs as `DPkg::Post-Invoke` after every dpkg operation.
   - Executes `sed -i 's|/data/data/com.termux/|/data/data/com.uncode/|g'` across all `/var/lib/dpkg/info/*` scripts and the `dpkg/status` database.
   - Catches any residual `com.termux` references in dpkg metadata.

3. **Post-Invoke Binary Patching ([98-uncode-patchelf](patches/etc/apt/apt.conf.d/98-uncode-patchelf) + [uncode-patchelf-hook.sh](patches/etc/apt/uncode-patchelf-hook.sh)):**
   - Runs as `DPkg::Post-Invoke` after every dpkg operation.
   - Uses a timestamp marker file (`$PREFIX/tmp/.uncode-last-install`) to identify recently modified files.
   - Scans `$PREFIX/bin`, `$PREFIX/lib`, `$PREFIX/libexec` for files newer than the marker.
   - Checks each file for the ELF magic bytes (`\x7fELF`).
   - Uses `perl -pi -e` to byte-patch `com.termux` → `com.uncode` in ELF binary data.
   - This fixes `DT_RUNPATH` (stored in `.dynstr`) and string constants (in `.rodata`) — safe because both names are exactly 10 bytes.

---

### Layer 3: Runtime Environment & Protection

1. **Shell Environment Init ([uncode-init.sh](patches/etc/profile.d/uncode-init.sh)):**
   - Sourced by `bash -l` (login shells) via the standard `/etc/profile.d/*.sh` mechanism.
   - Only activates if `TERMUX__PREFIX` is not already set (avoids conflicts with app-level env).
   - Exports corrected environment variables:
     - `PREFIX=/data/data/com.uncode/files/usr`
     - `HOME=/data/data/com.uncode/files/home`
     - `TMPDIR=$PREFIX/tmp`
     - `LANG=en_US.UTF-8`
     - `PATH=$PREFIX/bin:$PREFIX/bin/applets:$PATH`

2. **APT Package Pinning ([uncode-pin-dpkg](patches/etc/apt/preferences.d/uncode-pin-dpkg)):**
   - Sets `Pin-Priority: 1` (below installed priority of 100) for critical packages: `dpkg`, `dpkg-dev`, `termux-exec`, `termux-tools`.
   - This prevents `apt upgrade` from automatically overwriting these packages with upstream versions that contain `com.termux` paths.
   - Packages can still be upgraded if explicitly needed for dependency resolution.

3. **Baseline Library Protection ([uncode-protect-libs](patches/etc/dpkg/dpkg.cfg.d/uncode-protect-libs)):**
   ```cfg
   path-exclude=/data/data/com.uncode/files/usr/lib/libc++_shared.so
   ```
   - Prevents upstream packages from overwriting the bootstrap's `libc++_shared.so` during `apt --fix-broken install` or toolchain updates.

---

## 3. Patch Files Reference Table

| Path | Category | Core Purpose |
|---|---|---|
| [build.sh](build.sh) | Build Script | Extracts upstream bootstrap, overlays patches, rewrites dpkg metadata via `sed`, byte-patches all binaries/scripts via `perl`, and packages `bootstrap-aarch64.zip`. |
| [patches/etc/profile.d/uncode-init.sh](patches/etc/profile.d/uncode-init.sh) | Environment Shim | Bootstraps `PREFIX`, `PATH`, `HOME`, and `TMPDIR` environment variables for login shells. |
| [patches/etc/apt/preferences.d/uncode-pin-dpkg](patches/etc/apt/preferences.d/uncode-pin-dpkg) | APT Pin Rule | Sets Pin-Priority 1 for `dpkg`, `termux-exec`, and `termux-tools` to prevent automatic upstream overwrites. |
| [patches/etc/dpkg/dpkg.cfg.d/uncode-protect-libs](patches/etc/dpkg/dpkg.cfg.d/uncode-protect-libs) | Dpkg Exclude Rule | Excludes `libc++_shared.so` from package unpack operations to protect the system baseline library. |
| [patches/etc/apt/apt.conf.d/97-uncode-pre-install](patches/etc/apt/apt.conf.d/97-uncode-pre-install) | APT Hook Config | Registers `Pre-Install-Pkgs` hook pointing to `uncode-pre-install-rewrite.sh`. |
| [patches/etc/apt/uncode-pre-install-rewrite.sh](patches/etc/apt/uncode-pre-install-rewrite.sh) | Pre-Install Script | Unpacks `.deb` packages, rewrites all text files containing `com.termux` paths, and repacks them. |
| [patches/etc/apt/apt.conf.d/99-uncode-rewrite-postinst](patches/etc/apt/apt.conf.d/99-uncode-rewrite-postinst) | APT Hook Config | Direct `DPkg::Post-Invoke` `sed` rule that cleans `/var/lib/dpkg/info/*` metadata files. |
| [patches/etc/apt/apt.conf.d/98-uncode-patchelf](patches/etc/apt/apt.conf.d/98-uncode-patchelf) | APT Hook Config | Registers `DPkg::Post-Invoke` hook pointing to `uncode-patchelf-hook.sh`. |
| [patches/etc/apt/uncode-patchelf-hook.sh](patches/etc/apt/uncode-patchelf-hook.sh) | Post-Invoke Script | Byte-patches `com.termux` → `com.uncode` in recently installed ELF binaries. |

---

## 4. Lifecycle Execution Summary (`apt install`)

1. **Pre-Unpack Phase:** `97-uncode-pre-install` unpacks `.deb` files, rewrites all text files (shebangs, maintainer scripts, configs) from `com.termux` to `com.uncode`, and repacks the archive.
2. **Unpack Phase:** Stock `dpkg` extracts the patched `.deb`. `uncode-protect-libs` prevents overwriting baseline libraries (`libc++_shared.so`).
3. **Post-Unpack Phase (Metadata):** `99-uncode-rewrite-postinst` runs `sed` on all dpkg metadata files in `/var/lib/dpkg/info/` and the status database.
4. **Post-Unpack Phase (Binaries):** `98-uncode-patchelf` identifies recently installed ELF binaries and byte-patches any remaining `com.termux` references in their binary data (RUNPATH, .rodata string constants).
