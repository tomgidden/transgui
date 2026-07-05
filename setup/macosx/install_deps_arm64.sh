#!/bin/sh

set -x
set -e

# Install a Lazarus/FPC toolchain for building Transmission Remote GUI natively
# on Apple Silicon (aarch64) macOS.
#
# This is the aarch64-only counterpart to install_deps.sh (which remains on the
# original Lazarus 2.0.8 / FPC 3.0.4 x86_64 stack). Keeping them separate means
# the existing x86_64 CI leg is untouched by this newer toolchain.
#
# NOTE for macOS 26 (Tahoe): the released LCL still has Cocoa layout-recursion
# issues on Tahoe. If you hit UI instability, build the Lazarus development
# (main) branch instead and point create_app_new_arm64.sh at it via LAZARUS_DIR.

lazarus_ver="4.8"
fpc_dmg="fpc-3.2.4rc1a.intelarm64-macosx.dmg"
fpc_pkg_glob="fpc-*-macosx.pkg"
lazarus_zip="lazarus-darwin-aarch64-${lazarus_ver}.zip"
sf_base="https://downloads.sourceforge.net/project/lazarus/Lazarus%20macOS%20aarch64/Lazarus%20${lazarus_ver}"
lazarus_dest="${LAZARUS_DEST:-$HOME/lazarus}"

if [ -n "${sourceforge_mirror-}" ]; then
  mirror_string="&use_mirror=${sourceforge_mirror}"
fi

# --- FPC compiler (system install, needs sudo) ---
if [ ! -x "$(command -v fpc 2>&1)" ]; then
  curl -fL "${sf_base}/${fpc_dmg}?r=&ts=$(date +%s)${mirror_string-}" -o "fpc.dmg"

  # Attach the DMG and capture the mount point. Avoid a pipeline so a failing
  # hdiutil can't be masked by a succeeding awk (POSIX sh has no pipefail).
  attach_out="$(hdiutil attach -nobrowse -readonly fpc.dmg)"
  mount_point="$(printf '%s\n' "$attach_out" | awk 'END{$1="";$2="";sub(/^  */,"");print}')"
  if [ -z "$mount_point" ] || [ ! -d "$mount_point" ]; then
    echo "Failed to determine FPC DMG mount point" >&2
    exit 1
  fi

  # Resolve the package glob to exactly one file before handing it to installer
  # (which accepts only a single -pkg argument). Deliberately unquoted: this
  # must glob-expand so multiple matches become multiple positional args.
  # shellcheck disable=SC2086
  set -- "$mount_point"/$fpc_pkg_glob
  if [ "$#" -ne 1 ] || [ ! -e "$1" ]; then
    echo "Expected exactly one $fpc_pkg_glob in DMG, found $#" >&2
    hdiutil detach "$mount_point" || true
    exit 1
  fi
  fpc_pkg="$1"

  sudo installer -pkg "$fpc_pkg" -target /
  hdiutil detach "$mount_point"
  rm -f fpc.dmg
fi

# --- Lazarus IDE / LCL (portable zip, no sudo) ---
# The macOS Lazarus zips extract into a nested "lazarus/" subdirectory, so the
# real lazbuild lands at "$lazarus_dest/lazarus/lazbuild". Detect either layout
# so we don't re-download on every run, and report the correct LAZARUS_DIR.
laz_bindir=""
for cand in "$lazarus_dest/lazarus" "$lazarus_dest"; do
  if [ -x "$cand/lazbuild" ]; then
    laz_bindir="$cand"
    break
  fi
done

if [ ! -x "$(command -v lazbuild 2>&1)" ] && [ -z "$laz_bindir" ]; then
  curl -fL "${sf_base}/${lazarus_zip}?r=&ts=$(date +%s)${mirror_string-}" -o "lazarus.zip"
  # Unmark quarantine before unzipping (required by the Lazarus macOS README).
  xattr -c lazarus.zip 2> /dev/null || true
  mkdir -p "$lazarus_dest"
  unzip -oq lazarus.zip -d "$lazarus_dest"
  rm -f lazarus.zip

  for cand in "$lazarus_dest/lazarus" "$lazarus_dest"; do
    if [ -x "$cand/lazbuild" ]; then
      laz_bindir="$cand"
      break
    fi
  done
  echo "Lazarus extracted to: ${laz_bindir:-$lazarus_dest}"
  echo "Build with:  LAZARUS_DIR=\"${laz_bindir:-$lazarus_dest}\" ./create_app_new_arm64.sh"
fi
