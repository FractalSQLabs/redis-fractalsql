#!/usr/bin/env bash
#
# scripts/package.sh — redis-fractalsql packaging.
#
# Assumes ./build.sh ${ARCH} has produced:
#   dist/${ARCH}/fractalsql.so
#
# Emits one .deb and one .rpm per arch into dist/packages/:
#   dist/packages/redis-fractalsql-amd64.deb
#   dist/packages/redis-fractalsql-amd64.rpm
#   dist/packages/redis-fractalsql-arm64.deb
#   dist/packages/redis-fractalsql-arm64.rpm
#
# One binary covers Redis 6.2 / 7.0 / 7.2 / 7.4 (and 8.x) — the Redis
# Modules ABI (REDISMODULE_APIVER_1) has been stable since Redis 4.0,
# so the package depends on redis-server / redis generically rather
# than pinning a specific major.
#
# Usage:
#   scripts/package.sh [amd64|arm64]     # default: amd64

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="1.0.0"
ITERATION="1"
DIST_DIR="dist/packages"
PKG_NAME="redis-fractalsql"
mkdir -p "${DIST_DIR}"

# Absolute repo root, captured before any -C chdir'd fpm invocation.
REPO_ROOT="$(pwd)"
for f in LICENSE LICENSE-THIRD-PARTY; do
    if [ ! -f "${REPO_ROOT}/${f}" ]; then
        echo "missing ${REPO_ROOT}/${f} — refusing to package without it" >&2
        exit 1
    fi
done

PKG_ARCH="${1:-amd64}"
case "${PKG_ARCH}" in
    amd64|arm64) ;;
    *)
        echo "unknown arch '${PKG_ARCH}' — expected amd64 or arm64" >&2
        exit 2
        ;;
esac

case "${PKG_ARCH}" in
    amd64) RPM_ARCH="x86_64"  ;;
    arm64) RPM_ARCH="aarch64" ;;
esac

SO="dist/${PKG_ARCH}/fractalsql.so"
if [ ! -f "${SO}" ]; then
    echo "missing ${SO} — run ./build.sh ${PKG_ARCH} first" >&2
    exit 1
fi

DEB_OUT="${DIST_DIR}/${PKG_NAME}-${PKG_ARCH}.deb"
RPM_OUT="${DIST_DIR}/${PKG_NAME}-${PKG_ARCH}.rpm"

# Build a staging root that mirrors the on-disk layout so fpm can
# just tar it up.
#
# LICENSE ledger: staged into /usr/share/doc/<pkg>/ via install -Dm0644
# BEFORE running fpm. Explicit fpm src=dst mappings break here — fpm's
# -C chroots absolute source paths too, so ${REPO_ROOT}/LICENSE gets
# resolved as ${STAGE}${REPO_ROOT}/LICENSE and fpm bails with
# "Cannot chdir to ...".
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

install -Dm0755 "${SO}" \
    "${STAGE}/usr/lib/redis/modules/fractalsql.so"
install -Dm0644 "${REPO_ROOT}/scripts/load_module.conf" \
    "${STAGE}/etc/redis/modules-available/fractalsql.conf"
install -Dm0644 "${REPO_ROOT}/LICENSE" \
    "${STAGE}/usr/share/doc/${PKG_NAME}/LICENSE"
install -Dm0644 "${REPO_ROOT}/LICENSE-THIRD-PARTY" \
    "${STAGE}/usr/share/doc/${PKG_NAME}/LICENSE-THIRD-PARTY"

echo "------------------------------------------"
echo "Packaging ${PKG_NAME} (${PKG_ARCH})"
echo "------------------------------------------"

DESC="FractalSQL: Stochastic Fractal Search module for Redis 6.2 / 7.0 / 7.2 / 7.4 (ABI-compatible with 8.x)"

# LuaJIT is statically linked into fractalsql.so — no libluajit-5.1-2
# (Debian) or luajit (RPM) runtime dependency is declared.
#
# The post-install hint advises the operator to add the loadmodule
# directive to redis.conf. We deliberately do NOT auto-edit the
# server config — silently rewriting the operator's redis.conf is
# an unwelcome surprise on a shared host.
fpm -s dir -t deb \
    -n "${PKG_NAME}" \
    -v "${VERSION}" \
    -a "${PKG_ARCH}" \
    --iteration "${ITERATION}" \
    --description "${DESC}" \
    --license "MIT" \
    --depends "libc6 (>= 2.38)" \
    --depends "redis-server" \
    --config-files /etc/redis/modules-available/fractalsql.conf \
    --after-install "${REPO_ROOT}/packaging/debian/postinst" \
    -C "${STAGE}" \
    -p "${DEB_OUT}" \
    usr etc

fpm -s dir -t rpm \
    -n "${PKG_NAME}" \
    -v "${VERSION}" \
    -a "${RPM_ARCH}" \
    --iteration "${ITERATION}" \
    --description "${DESC}" \
    --license "MIT" \
    --depends "redis" \
    --config-files /etc/redis/modules-available/fractalsql.conf \
    --after-install "${REPO_ROOT}/packaging/debian/postinst" \
    -C "${STAGE}" \
    -p "${RPM_OUT}" \
    usr etc

rm -rf "${STAGE}"
trap - EXIT

echo
echo "Done. Packages in ${DIST_DIR}:"
ls -l "${DIST_DIR}"
