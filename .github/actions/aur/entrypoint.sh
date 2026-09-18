#!/usr/bin/env bash
set -euo pipefail

: "${INPUT_MODE:?mode is required}"
: "${INPUT_PACKAGES:?packages is required}"

BUILD_ROOT=/build

group() { echo "::group::$*"; }
endgroup() { echo "::endgroup::"; }
fail() {
  echo "::error::$*"
  exit 1
}

# Arch Linux ARM mirrors are noticeably less reliable than the official ones,
# so every pacman transaction gets a few attempts before we give up.
pacman_retry() {
  local attempt
  for attempt in 1 2 3; do
    if pacman "$@"; then
      return 0
    fi
    echo "pacman $* failed (attempt ${attempt}/3), retrying in 10s..."
    sleep 10
  done
  fail "pacman $* failed after 3 attempts"
}

group "Bootstrapping container"
# Official Arch and Arch Linux ARM ship different keyrings; install whichever
# this image actually provides so signature checks keep working.
pacman_retry -Sy --noconfirm
for keyring in archlinux-keyring archlinuxarm-keyring; do
  if pacman -Si "$keyring" &>/dev/null; then
    pacman_retry -S --noconfirm --needed "$keyring"
  fi
done
pacman_retry -Syu --noconfirm --needed git pacman-contrib sudo

# makepkg refuses to run as root, and --syncdeps shells out to sudo pacman.
if ! id builder &>/dev/null; then
  useradd -m builder
fi
echo 'builder ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/builder
chmod 0440 /etc/sudoers.d/builder
endgroup

# runuser resets HOME and does not reliably forward exported variables, but the
# factorio PKGBUILD authenticates with FACTORIO_* and caches its token under
# $HOME, so both are passed through explicitly instead of being inherited.
as_builder() {
  runuser -u builder -- env \
    HOME=/home/builder \
    FACTORIO_LOGIN="${FACTORIO_LOGIN:-}" \
    FACTORIO_TOKEN="${FACTORIO_TOKEN:-}" \
    "$@"
}

prepare_package() {
  local pkg=$1
  local src="/workspace/${pkg}"
  local dst="${BUILD_ROOT}/${pkg}"

  [[ -f "${src}/PKGBUILD" ]] || fail "${pkg}: no PKGBUILD found"

  install -d -o builder -g builder "$dst"
  cp -a "${src}/." "$dst/"
  chown -R builder:builder "$dst"

  group "${pkg}: updpkgsums"
  # makepkg -g downloads every declared arch's sources and emits checksums for
  # all of them, so a single amd64 run keeps b2sums_aarch64 correct too.
  as_builder bash -c "cd '${dst}' && updpkgsums"
  endgroup

  group "${pkg}: regenerate .SRCINFO"
  as_builder bash -c "cd '${dst}' && makepkg --printsrcinfo" >"${dst}/.SRCINFO.tmp"
  mv "${dst}/.SRCINFO.tmp" "${dst}/.SRCINFO"
  endgroup

  cp -f "${dst}/PKGBUILD" "${dst}/.SRCINFO" "${src}/"
  # The workspace is bind-mounted from the host runner, which is not root.
  chown "$(stat -c '%u:%g' "$src")" "${src}/PKGBUILD" "${src}/.SRCINFO"

  group "${pkg}: resulting metadata"
  grep -E '^\s*(arch|pkgver|pkgrel|[a-z0-9]+sums(_\w+)?) = ' "${dst}/.SRCINFO" || true
  endgroup
}

build_package() {
  local pkg=$1
  local src="/workspace/${pkg}"
  local dst="${BUILD_ROOT}/${pkg}"

  : "${INPUT_ARCH:?arch is required for mode 'build'}"

  local carch
  carch=$(bash -c 'source /etc/makepkg.conf; printf "%s" "$CARCH"')
  [[ "$carch" == "$INPUT_ARCH" ]] ||
    fail "${pkg}: container CARCH is '${carch}' but this job expects '${INPUT_ARCH}' - wrong runner/image pairing"
  echo "${pkg}: building natively for CARCH=${carch}"

  install -d -o builder -g builder "$dst"
  cp -a "${src}/." "$dst/"
  chown -R builder:builder "$dst"

  group "${pkg}: makepkg (CARCH=${carch})"
  # --syncdeps lets makepkg resolve depends/makedepends/checkdepends itself,
  # including the depends_<arch> variants, so nothing here parses the PKGBUILD.
  as_builder bash -c "cd '${dst}' && makepkg --syncdeps --noconfirm --needed"
  endgroup

  group "${pkg}: built packages"
  find "$dst" -maxdepth 1 -name '*.pkg.tar*' -printf '%f\t%s bytes\n'
  endgroup
}

read -ra packages <<<"$INPUT_PACKAGES"
[[ ${#packages[@]} -gt 0 ]] || fail "no packages given"

case "$INPUT_MODE" in
prepare)
  for pkg in "${packages[@]}"; do
    prepare_package "$pkg"
  done
  ;;
build)
  [[ ${#packages[@]} -eq 1 ]] || fail "mode 'build' takes exactly one package, got ${#packages[@]}"
  build_package "${packages[0]}"
  ;;
*)
  fail "unknown mode '${INPUT_MODE}' (expected 'prepare' or 'build')"
  ;;
esac
