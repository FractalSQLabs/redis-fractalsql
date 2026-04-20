# syntax=docker/dockerfile:1.7
#
# redis-fractalsql Factory build — zero-dependency posture.
#
# Produces ONE fractalsql.so per target architecture (driven by
# --platform). The Redis Modules ABI (REDISMODULE_APIVER_1) has been
# stable since Redis 4.0, so a single .so works on every supported
# major — 6.2 / 7.0 / 7.2 / 7.4 (and 8.x). Release packages depend on
# redis-server / redis generically rather than pinning a version.
#
# Build posture
#   LuaJIT is compiled from source as a PIC static archive and folded
#   into fractalsql.so. The resulting module depends on glibc only:
#   no libluajit-5.1.so, no libstdc++, no dynamic C++ ABI.
#
# Output (collected in the final `export` stage, emitted to the host
# via `docker buildx --output type=local,dest=...`):
#   /fractalsql.so
#
# Usage:
#   DOCKER_BUILDKIT=1 docker buildx build \
#     --platform linux/amd64 \
#     --target export \
#     --output type=local,dest=./dist/amd64 \
#     -f docker/Dockerfile .
#
# build.sh drives this for amd64 and arm64 in turn.
#
# --------------------------------------------------------------------
# Important build-system notes:
#
#  * The distro libluajit-5.1-dev ships a non-PIC .a, which fails to
#    link into a .so on most toolchains. We build LuaJIT 2.1 ourselves
#    with -fPIC + BUILDMODE=static and stage it into /opt/luajit.
#
#  * We clone LuaJIT from the GitHub mirror, not luajit.org/git. The
#    latter serves dumb HTTP and doesn't advertise shallow-clone
#    capabilities, so `git clone --depth=1` fails with "dumb http
#    transport does not support shallow capabilities".
#
#  * -fvisibility=hidden is deliberately NOT set on the TU defining
#    RedisModule_OnLoad. Redis's dlopen loader resolves the entry
#    point through the .so's .dynsym; hiding it breaks MODULE LOAD.
#
#  * redismodule.h is a self-contained header fetched by shallow-
#    cloning the Redis source at a pinned tag from the GitHub mirror.
#    We do NOT #define REDISMODULE_CORE — that macro is for Redis core
#    itself and switches the header to direct-call mode expecting a
#    linked libredis. Modules route every call through the function-
#    pointer table that RedisModule_Init populates.
#
#  * Post-link assertions (ldd / nm / size / exports) run in the
#    builder stage so the build fails fast if a dynamic luajit or
#    libstdc++ dependency sneaks back in, or if RedisModule_OnLoad
#    falls out of .dynsym.

# --------------------------------------------------------------------
# GLOBAL ARGs — declared before the first FROM so every stage below
# can re-import them with bare `ARG NAME` and pick up these defaults.
# ARGs declared INSIDE a stage are stage-scoped; later stages that
# re-import them pick up empty strings, which silently drops flags.
# --------------------------------------------------------------------
ARG LUAJIT_GIT_URL=https://github.com/LuaJIT/LuaJIT.git
ARG LUAJIT_GIT_REF=v2.1

# Redis 7.4 is a current LTS-adjacent stable release and ships a
# redismodule.h that carries the full REDISMODULE_APIVER_1 surface
# used by 6.2 / 7.0 / 7.2 / 7.4. Compiling against it yields a .so
# that loads cleanly on every one of those server versions.
ARG REDIS_GIT_URL=https://github.com/redis/redis.git
ARG REDIS_GIT_REF=7.4.1

# EXT_CFLAGS / EXT_LDFLAGS — the hardened flag set for fractalsql.so.
#
# -D_GLIBCXX_USE_CXX11_ABI=0: pre-C++11 std::string ABI; symbols never
#   reference __cxx11::basic_string even if the toolchain pulls
#   libstdc++ headers.
# -ffunction-sections / -fdata-sections: per-symbol section emission,
#   pairs with -Wl,--gc-sections to drop unused LuaJIT code paths.
# -fvisibility=default: RedisModule_OnLoad must live in .dynsym. If
#   any upstream CFLAGS injects -fvisibility=hidden later, the last
#   -fvisibility=* on the gcc command line wins and restores
#   visibility. We want this AFTER any other visibility flag — the
#   Dockerfile controls the invocation order.
# -static-libgcc / -static-libstdc++: link the C/C++ runtime helpers
#   statically; combined with --exclude-libs,ALL they stay invisible
#   in .dynsym.
# -Wl,--strip-all: drop .symtab. .dynsym survives, which is what the
#   Redis loader needs for RedisModule_OnLoad resolution.
ARG EXT_CFLAGS="-D_GLIBCXX_USE_CXX11_ABI=0 -ffunction-sections -fdata-sections -fvisibility=default"
ARG EXT_LDFLAGS="-static-libgcc -static-libstdc++ -Wl,--gc-sections -Wl,--strip-all -Wl,--exclude-libs,ALL"

# Ceiling on the resulting .so. Generous (3 MiB) — fractalsql.so on
# amd64 lands comfortably under 1 MiB. Bump only with a note in the
# commit message; unexpected growth usually means something got
# linked in that shouldn't have.
ARG SIZE_CEILING_BYTES=3145728

# --------------------------------------------------------------------
# Stage: PIC-built LuaJIT static archive.
# --------------------------------------------------------------------
FROM debian:bookworm-slim AS luajit-static
ARG LUAJIT_GIT_URL
ARG LUAJIT_GIT_REF
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential ca-certificates git \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth=1 --branch "${LUAJIT_GIT_REF}" \
        "${LUAJIT_GIT_URL}" /src/luajit
WORKDIR /src/luajit
# BUILDMODE=static avoids producing the .so we don't need; XCFLAGS=-fPIC
# makes the .a foldable into a downstream shared object. Explicit
# TARGET_ARCH= unset because LuaJIT's Makefile uses it as a gcc flag
# knob — any outer env value makes gcc treat it as a linker input.
RUN unset TARGET_ARCH \
 && make BUILDMODE=static XCFLAGS="-fPIC" PREFIX=/opt/luajit -j"$(nproc)" TARGET_ARCH= \
 && make install BUILDMODE=static PREFIX=/opt/luajit \
 && test -f /opt/luajit/lib/libluajit-5.1.a \
 && ! test -f /opt/luajit/lib/libluajit-5.1.so

# --------------------------------------------------------------------
# Stage: harvest redismodule.h from the pinned Redis source tag.
# redismodule.h is a single self-contained header; no secondary
# includes are pulled in. Shallow clone, copy the one file, done.
# --------------------------------------------------------------------
FROM debian:bookworm-slim AS redis-header
ARG REDIS_GIT_URL
ARG REDIS_GIT_REF
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates git \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth=1 --branch "${REDIS_GIT_REF}" \
        "${REDIS_GIT_URL}" /src/redis \
 && test -f /src/redis/src/redismodule.h \
 && install -Dm0644 /src/redis/src/redismodule.h /out/redismodule.h

# --------------------------------------------------------------------
# Stage: fractalsql.so builder. One stage covers all Redis majors —
# the module ABI (REDISMODULE_APIVER_1) has been stable since Redis
# 4.0, so one .so per arch covers 6.2 / 7.0 / 7.2 / 7.4 (and 8.x).
# --------------------------------------------------------------------
FROM debian:bookworm-slim AS builder
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential \
        binutils \
        file \
        pkg-config \
 && rm -rf /var/lib/apt/lists/*
COPY --from=luajit-static /opt/luajit /opt/luajit
COPY --from=redis-header  /out/redismodule.h /build/include/redismodule.h

WORKDIR /build
COPY src/                /build/src/
COPY include/            /build/include/
COPY docker/assert_so.sh /build/docker/assert_so.sh

# Re-import the global ARGs into this stage. Bare `ARG NAME` — no
# default — pulls in the value declared before the first FROM.
ARG EXT_CFLAGS
ARG EXT_LDFLAGS
ARG SIZE_CEILING_BYTES

RUN set -eux; \
    gcc -Wall -Wextra -O3 -fPIC \
        -I/opt/luajit/include/luajit-2.1 \
        -Iinclude \
        ${EXT_CFLAGS} \
        -shared -o /fractalsql.so \
        src/module.c \
        /opt/luajit/lib/libluajit-5.1.a \
        -lm -ldl -lpthread \
        ${EXT_LDFLAGS}; \
    sh /build/docker/assert_so.sh /fractalsql.so "${SIZE_CEILING_BYTES}"

# --------------------------------------------------------------------
# Export stage — scratch, so `buildx --output=local` drops just the
# .so file onto the host.
# --------------------------------------------------------------------
FROM scratch AS export
COPY --from=builder /fractalsql.so /fractalsql.so
