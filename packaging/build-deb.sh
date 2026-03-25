#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-deb.sh <amd64|arm64>

Environment:
  PACKAGE_NAME     Debian package name to emit.
                   Default: ddt-awg
  PACKAGE_VERSION  Debian package version.
                   Default: derived from the parent repository state
  MAINTAINER       Maintainer string for the package metadata.
                   Default: AWG Build Workflow <41898282+github-actions[bot]@users.noreply.github.com>
  OUTPUT_DIR       Directory where the .deb is written.
                   Default: <repo>/dist
  BUILD_ROOT       Scratch directory for intermediate files.
                   Default: <repo>/.build
EOF
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

PACKAGE_NAME="${PACKAGE_NAME:-ddt-awg}"
MAINTAINER="${MAINTAINER:-AWG Build Workflow <41898282+github-actions[bot]@users.noreply.github.com>}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/dist}"
BUILD_ROOT="${BUILD_ROOT:-${REPO_ROOT}/.build}"

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

ARCH="$1"
case "${ARCH}" in
  amd64)
    GOARCH="amd64"
    CC_CANDIDATES=("x86_64-linux-gnu-gcc" "gcc")
    STRIP_CANDIDATES=("x86_64-linux-gnu-strip" "strip")
    ;;
  arm64)
    GOARCH="arm64"
    CC_CANDIDATES=("aarch64-linux-gnu-gcc")
    STRIP_CANDIDATES=("aarch64-linux-gnu-strip")
    ;;
  *)
    echo "Unsupported architecture: ${ARCH}" >&2
    usage
    exit 1
    ;;
esac

pick_tool() {
  local candidate

  for candidate in "$@"; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

debian_version() {
  local exact_tag
  local short_sha
  local timestamp

  if [[ -n "${PACKAGE_VERSION:-}" ]]; then
    printf '%s\n' "${PACKAGE_VERSION}"
    return 0
  fi

  if exact_tag=$(git -C "${REPO_ROOT}" describe --tags --exact-match 2>/dev/null); then
    exact_tag="${exact_tag#v}"
    exact_tag="${exact_tag//-/.}"
    printf '%s\n' "${exact_tag}"
    return 0
  fi

  short_sha=$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || printf 'local')
  timestamp=$(date -u +%Y%m%d%H%M%S)
  printf '0.0~git%s.%s\n' "${timestamp}" "${short_sha}"
}

CC=$(pick_tool "${CC_CANDIDATES[@]}" || true)
STRIP_BIN=$(pick_tool "${STRIP_CANDIDATES[@]}" || true)

if [[ -z "${CC}" ]]; then
  echo "No suitable C compiler found for ${ARCH}" >&2
  exit 1
fi

if [[ -z "${STRIP_BIN}" ]]; then
  echo "No suitable strip binary found for ${ARCH}" >&2
  exit 1
fi

PACKAGE_VERSION="$(debian_version)"
WORK_DIR="${BUILD_ROOT}/${ARCH}"
PKG_ROOT="${WORK_DIR}/pkg"
DEBIAN_DIR="${PKG_ROOT}/DEBIAN"
DOC_DIR="${PKG_ROOT}/usr/share/doc/${PACKAGE_NAME}"
PACKAGE_FILE="${OUTPUT_DIR}/${PACKAGE_NAME}_${PACKAGE_VERSION}_${ARCH}.deb"

COMMON_INSTALL_ARGS=(
  "WITH_BASHCOMPLETION=yes"
  "WITH_WGQUICK=yes"
  "WITH_SYSTEMDUNITS=yes"
  "PLATFORM=linux"
)

PACKAGE_RELATIONS=""
if [[ "${PACKAGE_NAME}" != "amneziawg-tools" ]]; then
  PACKAGE_RELATIONS=$'Provides: amneziawg-tools\nConflicts: amneziawg-tools\nReplaces: amneziawg-tools'
fi

rm -rf "${WORK_DIR}"
mkdir -p "${DEBIAN_DIR}" "${OUTPUT_DIR}" "${DOC_DIR}"

make -C "${REPO_ROOT}/amneziawg-go" clean
env CGO_ENABLED=0 GOOS=linux GOARCH="${GOARCH}" make -C "${REPO_ROOT}/amneziawg-go" amneziawg-go

make -C "${REPO_ROOT}/amneziawg-tools/src" clean
make -C "${REPO_ROOT}/amneziawg-tools/src" CC="${CC}" "${COMMON_INSTALL_ARGS[@]}" install DESTDIR="${PKG_ROOT}"

install -Dm0755 "${REPO_ROOT}/amneziawg-go/amneziawg-go" "${PKG_ROOT}/usr/bin/amneziawg-go"

"${STRIP_BIN}" --strip-unneeded "${PKG_ROOT}/usr/bin/awg" || true
"${STRIP_BIN}" --strip-unneeded "${PKG_ROOT}/usr/bin/amneziawg-go" || true

cp "${REPO_ROOT}/amneziawg-go/README.md" "${DOC_DIR}/README.amneziawg-go.md"
cp "${REPO_ROOT}/amneziawg-go/LICENSE" "${DOC_DIR}/LICENSE.amneziawg-go"
cp "${REPO_ROOT}/amneziawg-tools/README.md" "${DOC_DIR}/README.amneziawg-tools.md"
cp "${REPO_ROOT}/amneziawg-tools/COPYING" "${DOC_DIR}/COPYING.amneziawg-tools"
gzip -n9 "${DOC_DIR}/README.amneziawg-go.md" "${DOC_DIR}/README.amneziawg-tools.md"

if [[ -d "${PKG_ROOT}/usr/share/man" ]]; then
  find "${PKG_ROOT}/usr/share/man" -type f -name '*.8' -exec gzip -n9 {} \;
fi

INSTALLED_SIZE=$(du -sk "${PKG_ROOT}" | cut -f1)

cat > "${DEBIAN_DIR}/control" <<EOF
Package: ${PACKAGE_NAME}
Version: ${PACKAGE_VERSION}
Section: net
Priority: optional
Architecture: ${ARCH}
Maintainer: ${MAINTAINER}
Installed-Size: ${INSTALLED_SIZE}
Depends: bash, iproute2, libc6
Recommends: nftables | iptables
Suggests: openresolv | resolvconf
${PACKAGE_RELATIONS}
Homepage: https://github.com/amnezia-vpn
Description: AmneziaWG userspace bundle with awg and amneziawg-go
 This package combines the AmneziaWG command-line utilities from
 amneziawg-tools with the amneziawg-go userspace backend.
 .
 It installs awg, awg-quick, bash completions, man pages, systemd units,
 and amneziawg-go in a single package.
EOF

chmod 0755 "${DEBIAN_DIR}"

dpkg-deb --build --root-owner-group "${PKG_ROOT}" "${PACKAGE_FILE}" >/dev/null
echo "Built ${PACKAGE_FILE}"
