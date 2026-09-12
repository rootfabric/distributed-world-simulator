#!/usr/bin/env bash
# A7 environment recovery: keep required graphics; never install into the host OS.
# Root cause: run 34701038458 stopped with XVFB_REQUIRED_FOR_COMPLETE_A7.
# All downloaded packages, extracted libraries and optional apt indices are job-local.
set -euo pipefail
: "${RUNNER_TEMP:?GitHub runner temporary directory is required}"
: "${GITHUB_PATH:?GitHub PATH sink is required}"
: "${GITHUB_ENV:?GitHub environment sink is required}"
mkdir -p artifacts/a7/environment
exec > >(tee artifacts/a7/environment/graphics-bootstrap.log) 2>&1
printf 'A7_GRAPHICS_BOOTSTRAP\n'
uname -a
if command -v xvfb-run >/dev/null 2>&1; then
  printf 'GRAPHICS_EXECUTOR=EXISTING_SYSTEM_XVFB\n'
  xvfb-run -a -s '-screen 0 1600x1100x24' /bin/true
  printf 'GRAPHICS_BOOTSTRAP_PASS\n'
  exit 0
fi
command -v apt-get >/dev/null
command -v dpkg-deb >/dev/null
prefix="$(mktemp -d "$RUNNER_TEMP/a7-graphics.XXXXXXXX")"
printf 'A7_GRAPHICS_PREFIX=%s\n' "$prefix" >> "$GITHUB_ENV"
mkdir -p "$prefix/packages" "$prefix/root"
packages=(xvfb xauth libxfont2 xserver-common x11-xkb-utils xkb-data xfonts-base libxmu6 libxmuu1 libfontenc1 libxau6 libxdmcp6 libxt6 libsm6 libice6)
(
  cd "$prefix/packages"
  # apt-get download checks distro package metadata; it does not install packages.
  if ! apt-get download "${packages[@]}"; then
    # Stale system package indices are not a reason to change the host or skip graphics.
    mkdir -p "$prefix/apt/lists/partial" "$prefix/apt/cache/archives/partial"
    cat > "$prefix/apt/isolated.conf" <<EOF
Dir::State::lists "$prefix/apt/lists";
Dir::Cache "$prefix/apt/cache";
Debug::NoLocking "true";
APT::Sandbox::User "$(id -un)";
#clear APT::Update::Post-Invoke;
#clear APT::Update::Post-Invoke-Success;
#clear DPkg::Post-Invoke;
EOF
    APT_CONFIG="$prefix/apt/isolated.conf" apt-get update
    APT_CONFIG="$prefix/apt/isolated.conf" apt-get download "${packages[@]}"
  fi
  for package in ./*.deb; do
    dpkg-deb --field "$package" Package Version Architecture
    sha256sum "$package"
    dpkg-deb --extract "$package" "$prefix/root"
  done
)
export PATH="$prefix/root/usr/bin:$PATH"
export LD_LIBRARY_PATH="$prefix/root/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export XKB_CONFIG_ROOT="$prefix/root/usr/share/X11/xkb"
printf '%s\n' "$prefix/root/usr/bin" >> "$GITHUB_PATH"
printf 'LD_LIBRARY_PATH=%s\nXKB_CONFIG_ROOT=%s\n' "$LD_LIBRARY_PATH" "$XKB_CONFIG_ROOT" >> "$GITHUB_ENV"
printf 'GRAPHICS_EXECUTOR=JOB_LOCAL_XVFB\n'
command -v xvfb-run
command -v Xvfb
ldd "$prefix/root/usr/bin/Xvfb"
if ldd "$prefix/root/usr/bin/Xvfb" | grep -q 'not found'; then
  printf 'GRAPHICS_DEPENDENCY_UNRESOLVED\n' >&2
  exit 1
fi
xvfb-run -a -s '-screen 0 1600x1100x24' /bin/true
printf 'GRAPHICS_BOOTSTRAP_PASS\n'
