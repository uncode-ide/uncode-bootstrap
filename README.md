# uncode-bootstrap

Minimal Termux-flavored userland tarball for **Uncode IDE** — an Android app with package name `com.uncode`.

## Overview

This project produces a `bootstrap-aarch64.zip` (~25 MB) that ships inside the Uncode IDE APK. At first launch the app extracts it into `/data/data/com.uncode/files/`, giving the user a fully working Linux-like environment with `bash`, `apt`, `coreutils`, `git`, and everything else a mobile developer needs.

### Why a custom bootstrap?

The upstream [Termux](https://github.com/termux/termux-packages) bootstrap hardcodes `/data/data/com.termux/` in thousands of places — inside ELF binaries, shell scripts, dpkg metadata, and APT configuration.
Because Android sandboxes each app to its own `/data/data/<package>/` prefix, a different package name means every one of those paths is wrong.

**Key insight:** `com.uncode` is exactly **10 bytes**, the same length as `com.termux`.
This makes byte-level patching of ELF binaries safe — no offsets shift, no sections need resizing.

### How it works

| Layer | Mechanism |
|---|---|
| **Build-time** | `build.sh` rewrites all dpkg metadata (`status`, `*.list`, `*.postinst`, …) via `sed` |
| **Install-time** | APT `DPkg::Pre-Install-Pkgs` hook rewrites `.deb` control scripts before `dpkg` unpacks them |
| **Post-install** | APT `DPkg::Post-Invoke` hooks re-sed dpkg info files and byte-patch new ELF binaries |
| **Runtime** | `etc/profile.d/uncode-init.sh` exports corrected `PREFIX`, `HOME`, `TMPDIR`, and `PATH` |

## Building

### Prerequisites

- A vanilla Termux bootstrap zip (standard `com.termux` build — `build.sh` handles the conversion)
- `zip`, `unzip`, `sed`, `perl`, `bash`

### Producing the vanilla bootstrap

```bash
git clone --depth=1 https://github.com/termux/termux-packages.git
cd termux-packages

# Build with default com.termux package name (requires Docker)
./scripts/run-docker.sh ./scripts/build-bootstraps.sh --architectures aarch64
```

This produces `bootstrap-archives/bootstrap-aarch64.zip` with standard `com.termux` paths.
`build.sh` will byte-patch all occurrences to `com.uncode` — this is safe because both
names are exactly 10 bytes, so no binary offsets shift.

### Applying Uncode patches

```bash
./build.sh path/to/bootstrap-aarch64.zip dist/uncode-bootstrap-aarch64.zip
```

The script:

1. Extracts the vanilla zip into a staging rootfs.
2. Copies everything under `patches/` into the rootfs (APT hooks, profile scripts, dpkg config).
3. Rewrites `/data/data/com.termux/` → `/data/data/com.uncode/` in all dpkg metadata files.
4. Re-zips the result with symlink preservation.

## Distribution

Releases ship a single artifact:

| File | Size | Description |
|---|---|---|
| `uncode-bootstrap-aarch64.zip` | ~25 MB | Ready-to-extract userland for arm64-v8a devices |

## CI / CD

The included [GitHub Actions workflow](.github/workflows/build-bootstrap.yml) automates the full pipeline:

1. Clones `termux-packages`.
2. Builds the vanilla bootstrap (with default `com.termux` prefix) inside Docker.
3. Applies Uncode patches via `build.sh` (byte-patches `com.termux` → `com.uncode`).
4. Uploads the artifact and creates a GitHub release.

## Patch inventory

| File | Purpose |
|---|---|
| `99-uncode-rewrite-postinst` | APT Post-Invoke: re-seds dpkg info files after every install |
| `98-uncode-patchelf` | APT Post-Invoke: byte-patches new ELF binaries |
| `97-uncode-pre-install` | APT Pre-Install-Pkgs: rewrites `.deb` control scripts in-place |
| `uncode-pin-dpkg` | APT pinning: prevents accidental overwrite of critical packages |
| `uncode-protect-libs` | dpkg path-exclude: protects `libc++_shared.so` |
| `uncode-init.sh` | Profile: exports corrected environment variables |

## License

This project re-packages Termux components which are licensed under the [GPLv3](https://github.com/termux/termux-packages/blob/master/LICENSE.md).
