#!/usr/bin/env bash
# Собирает libbox.aar для Android из upstream SagerNet/sing-box.
#
# Выход: mobile/android/app/libs/libbox.aar (~25 MB, все ABI внутри одного AAR).
#
# Документация: wiki/operations/build-libbox-aar.md
# План эпика: wiki/queries/mobile-step-19-final-plan.md
#
# Требования: Go 1.24+ (sing-box v1.13.14), sagernet/gomobile v0.1.12, NDK 28.0.13004108,
# ANDROID_HOME, JAVA_HOME (OpenJDK 17).

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MOBILE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly LIBS_DIR="${MOBILE_DIR}/android/app/libs"
readonly OUTPUT_AAR="${LIBS_DIR}/libbox.aar"

SINGBOX_VERSION="${SINGBOX_VERSION:-1.13.14}"
SINGBOX_REPO="${SINGBOX_REPO:-https://github.com/SagerNet/sing-box.git}"
WORKDIR="${WORKDIR:-${TMPDIR:-/tmp}/sing-box-build-${SINGBOX_VERSION}}"
SKIP_BUILD="${SKIP_BUILD:-0}"
# Pinned to github.com/sagernet/gomobile in sing-box v1.13.14 go.mod (supports -libname flag).
GOMOBILE_VERSION="${GOMOBILE_VERSION:-v0.1.12}"

log() {
    printf '[build-libbox] %s\n' "$*"
}

die() {
    printf '[build-libbox] ERROR: %s\n' "$*" >&2
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "command not found: $1"
}

require_env() {
    if [[ -z "${!1:-}" ]]; then
        die "environment variable $1 must be set"
    fi
}

check_go_version() {
    local go_version
    go_version="$(go env GOVERSION | sed 's/^go//')"
    local major minor
    IFS='.' read -r major minor _ <<<"${go_version}"
    if (( major < 1 || (major == 1 && minor < 24) )); then
        die "Go 1.24+ required for sing-box v${SINGBOX_VERSION} (found go${go_version})"
    fi
    log "Go version OK: go${go_version}"
}

check_java_version() {
    require_env JAVA_HOME
    local java_bin="${JAVA_HOME}/bin/java"
    [[ -x "${java_bin}" ]] || die "JAVA_HOME/bin/java not executable: ${java_bin}"

    local java_version
    java_version="$("${java_bin}" --version 2>&1 | head -n1)"
    if [[ "${java_version}" != *"17"* ]]; then
        die "OpenJDK 17 required (upstream checkJavaVersion). Found: ${java_version}"
    fi
    log "Java version OK: ${java_version}"
}

check_android_sdk() {
    require_env ANDROID_HOME
    [[ -d "${ANDROID_HOME}" ]] || die "ANDROID_HOME is not a directory: ${ANDROID_HOME}"

    if [[ ! -d "${ANDROID_HOME}/platforms/android-23" && ! -d "${ANDROID_HOME}/platforms/android-34" ]]; then
        log "WARN: android-23 platform not found under ANDROID_HOME/platforms"
        log "      Install via: sdkmanager \"platforms;android-34\""
    fi

    if [[ -z "$(find "${ANDROID_HOME}/ndk" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1 || true)" ]]; then
        log "WARN: no NDK found under ANDROID_HOME/ndk"
        log "      Install via: sdkmanager \"ndk;28.0.13004108\""
    fi

    log "ANDROID_HOME OK: ${ANDROID_HOME}"
}

install_gomobile() {
    log "Installing sagernet/gomobile ${GOMOBILE_VERSION} (upstream fork, supports -libname)"
    go install "github.com/sagernet/gomobile/cmd/gomobile@${GOMOBILE_VERSION}"
    go install "github.com/sagernet/gomobile/cmd/gobind@${GOMOBILE_VERSION}"
    gomobile init
}

check_gomobile() {
    local gobin gomobile_bin gobind_bin
    gobin="$(go env GOPATH)/bin"
    gomobile_bin="${gobin}/gomobile"
    gobind_bin="${gobin}/gobind"

    if [[ ! -x "${gomobile_bin}" || ! -x "${gobind_bin}" ]]; then
        install_gomobile
        gomobile_bin="${gobin}/gomobile"
        gobind_bin="${gobin}/gobind"
    fi

    [[ -x "${gomobile_bin}" ]] || die "gomobile not found after install: ${gomobile_bin}"
    [[ -x "${gobind_bin}" ]] || die "gobind not found after install: ${gobind_bin}"
    log "gomobile OK: ${gomobile_bin} (${GOMOBILE_VERSION})"
}

prepare_singbox_source() {
    local tag="v${SINGBOX_VERSION}"

    if [[ ! -d "${WORKDIR}/.git" ]]; then
        log "Cloning ${SINGBOX_REPO} (tag ${tag}) into ${WORKDIR}"
        git clone --depth 1 --branch "${tag}" "${SINGBOX_REPO}" "${WORKDIR}"
    else
        log "Using existing clone: ${WORKDIR}"
        git -C "${WORKDIR}" fetch --tags --depth 1 origin "${tag}" 2>/dev/null || true
        git -C "${WORKDIR}" checkout "${tag}"
    fi

    log "Initializing submodules (sing-tun and deps)..."
    git -C "${WORKDIR}" submodule update --init --recursive
}

build_aar() {
    log "Building libbox.aar via: go run ./cmd/internal/build_libbox -target android"
    log "This may take 10-20 minutes on first run (NDK toolchain download)."
    (
        cd "${WORKDIR}"
        go run ./cmd/internal/build_libbox -target android
    )

    [[ -f "${WORKDIR}/libbox.aar" ]] || die "build finished but ${WORKDIR}/libbox.aar not found"
    if [[ -f "${WORKDIR}/libbox-legacy.aar" ]]; then
        log "Also built libbox-legacy.aar (API 21, without naive outbound) — not copied to project"
    fi
}

verify_aar() {
    local aar_path="$1"
    require_cmd unzip

    # gomobile bind stores native libs under jni/<abi>/libbox.so (not lib/<abi>/)
    if ! unzip -l "${aar_path}" | grep -q 'libbox\.so'; then
        die "AAR does not contain libbox.so: ${aar_path}"
    fi

    log "AAR contents (native libs):"
    unzip -l "${aar_path}" | grep 'libbox\.so' || true

    if command -v jar >/dev/null 2>&1; then
        local classes_jar
        classes_jar="$(mktemp /tmp/libbox-classes.XXXXXX.jar)"
        unzip -p "${aar_path}" classes.jar > "${classes_jar}"
        log "Java package namespace (first 15 entries):"
        jar tf "${classes_jar}" | head -15 || true
        rm -f "${classes_jar}"
    fi
}

install_aar() {
    mkdir -p "${LIBS_DIR}"
    cp "${WORKDIR}/libbox.aar" "${OUTPUT_AAR}"
    log "Installed: ${OUTPUT_AAR} ($(du -h "${OUTPUT_AAR}" | cut -f1))"
}

print_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${OUTPUT_AAR}"
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${OUTPUT_AAR}"
    else
        log "sha256sum/shasum not found — skip checksum"
    fi
}

main() {
    log "sing-box version: v${SINGBOX_VERSION}"
    log "workdir: ${WORKDIR}"
    log "output: ${OUTPUT_AAR}"

    require_cmd go
    require_cmd git
    check_go_version
    check_java_version
    check_android_sdk
    check_gomobile

    prepare_singbox_source

    if [[ "${SKIP_BUILD}" == "1" && -f "${WORKDIR}/libbox.aar" ]]; then
        log "SKIP_BUILD=1 and libbox.aar exists — skipping gomobile bind"
    else
        build_aar
    fi

    verify_aar "${WORKDIR}/libbox.aar"
    install_aar
    print_sha256

    log "Done. Next: git add -f mobile/android/app/libs/libbox.aar (Commit 2)"
}

main "$@"
