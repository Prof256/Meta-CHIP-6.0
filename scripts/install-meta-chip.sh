#!/usr/bin/env bash
# =============================================================================
#  meta-chip-6.0 Bootstrap Installer (Linux only)
# -----------------------------------------------------------------------------
#  Downloads the meta-chip-6.0 layer, installs the Yocto host toolchain for
#  your distribution, creates a dedicated Python virtualenv with bitbake-setup,
#  and then hands off to scripts/setup-chip.py for interactive configuration.
#
#  Usage (one-liner):
#    bash <(curl -fsSL https://raw.githubusercontent.com/Prof256/meta-chip-6.0/main/scripts/install-meta-chip.sh)
#
#  Usage (already downloaded):
#    ./install-meta-chip.sh [options] -- [setup-chip.py options]
#
#  Options:
#    -d, --dir DIR        Install directory          (default: ~/meta-chip-6.0)
#    -b, --branch REF     Git branch/tag/SHA         (default: main)
#    -r, --repo URL       Repository URL             (default: GitHub Prof256)
#        --no-deps        Skip system package installation
#        --yes            Assume "yes" (non-interactive; installs packages)
#        --no-configure   Bootstrap only, do not run the configuration wizard
#        --check          Only run diagnostics, change nothing, exit
#        --with-init      Pass --init to setup-chip.py (runs bitbake-setup init)
#    -h, --help           Show this help
#
#  Anything after "--" is forwarded verbatim to scripts/setup-chip.py, e.g.:
#    ./install-meta-chip.sh --yes -- --profile 1 --nand 1 --branch 1
#
#  Supported distros: Debian/Ubuntu/Mint, Fedora/RHEL/CentOS/Rocky, Arch/Manjaro,
#  openSUSE/SLES. Other Linux distributions are supported via --no-deps.
# =============================================================================

set -Eeuo pipefail

# ----------------------------------------------------------------------------
# Defaults
# ----------------------------------------------------------------------------
REPO_URL="https://github.com/Prof256/meta-chip-6.0"
REPO_REF="main"
INSTALL_DIR="${HOME}/meta-chip-6.0"
VENV_DIR="${HOME}/.yocto-chip-venv"
INSTALL_DEPS=1
ASSUME_YES=0
RUN_CONFIGURE=1
CHECK_ONLY=0
SETUP_INIT_HANDOFF=0
FORWARD_ARGS=()

MIN_DISK_GB=50

# ----------------------------------------------------------------------------
# Output helpers (no colour when not on a TTY)
# ----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
    C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

banner() {
    printf '%s\n' "${C_BOLD}${C_BLUE}"
    printf '%s\n' "=============================================================="
    printf '%s\n' " Next Thing Co. C.H.I.P. - Yocto 6.0 Layer Bootstrap Installer"
    printf '%s\n' "=============================================================="
    printf '%s\n' "${C_RESET}"
}

info()  { printf '%s[INFO]%s %s\n'  "${C_BLUE}"   "${C_RESET}" "$*"; }
ok()    { printf '%s[ OK ]%s %s\n'  "${C_GREEN}"  "${C_RESET}" "$*"; }
warn()  { printf '%s[WARN]%s %s\n'  "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
die()   { printf '%s[FAIL]%s %s\n'  "${C_RED}"    "${C_RESET}" "$*" >&2; exit 1; }

on_error() {
    local rc=$?
    printf '%s[FAIL]%s Unexpected error at line %s (exit %s)\n' \
        "${C_RED}" "${C_RESET}" "${BASH_LINENO[0]}" "${rc}" >&2
    exit "${rc}"
}
trap on_error ERR

usage() {
    cat <<'USAGE_EOF'
meta-chip-6.0 Bootstrap Installer (Linux only)

Usage:
  bash <(curl -fsSL https://raw.githubusercontent.com/Prof256/meta-chip-6.0/main/scripts/install-meta-chip.sh)
  ./install-meta-chip.sh [options] -- [setup-chip.py options]

Options:
  -d, --dir DIR        Install directory          (default: ~/meta-chip-6.0)
  -b, --branch REF     Git branch/tag/SHA         (default: main)
  -r, --repo URL       Repository URL             (default: GitHub Prof256)
      --no-deps        Skip system package installation
  -y, --yes            Assume "yes" (installs packages non-interactively)
      --no-configure   Bootstrap only, do not run the configuration wizard
      --check          Run diagnostics only, change nothing, exit
      --with-init      Pass --init to setup-chip.py (runs bitbake-setup init)
  -h, --help           Show this help

Anything after "--" is forwarded verbatim to scripts/setup-chip.py, e.g.:
  ./install-meta-chip.sh --yes -- --profile 1 --nand 1 --branch 1

Supported package managers: apt, dnf, yum, pacman, zypper.
Other distributions: use --no-deps and install the host packages manually.
USAGE_EOF
    exit 0
}

# ----------------------------------------------------------------------------
# Argument parsing
# ----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)        INSTALL_DIR="$2"; shift 2 ;;
        -b|--branch)     REPO_REF="$2"; shift 2 ;;
        -r|--repo)       REPO_URL="$2"; shift 2 ;;
        --no-deps)       INSTALL_DEPS=0; shift ;;
        --yes|-y)        ASSUME_YES=1; shift ;;
        --no-configure)  RUN_CONFIGURE=0; shift ;;
        --check)         CHECK_ONLY=1; INSTALL_DEPS=0; RUN_CONFIGURE=0; shift ;;
        --with-init)     SETUP_INIT_HANDOFF=1; shift ;;
        -h|--help)       usage ;;
        --)              shift; FORWARD_ARGS=("$@"); break ;;
        *)               die "Unknown option: $1 (try --help)" ;;
    esac
done

[[ "${INSTALL_DIR}" == "~"* ]] && INSTALL_DIR="${HOME}${INSTALL_DIR#\~}"

# ----------------------------------------------------------------------------
# Preconditions: Linux + bash
# ----------------------------------------------------------------------------
require_linux() {
    [[ "${OSTYPE:-}" == linux* ]] || die "This installer is Linux only (detected: ${OSTYPE:-unknown})."
}

require_non_root() {
    if [[ ${EUID} -eq 0 ]]; then
        warn "Running as root. Yocto discourages this and you will get a warning."
        warn "Prefer running as a normal user; sudo is used only where required."
    fi
}

detect_pkg_manager() {
    if   command -v apt-get >/dev/null 2>&1; then echo "apt"
    elif command -v dnf     >/dev/null 2>&1; then echo "dnf"
    elif command -v yum     >/dev/null 2>&1; then echo "yum"
    elif command -v pacman  >/dev/null 2>&1; then echo "pacman"
    elif command -v zypper  >/dev/null 2>&1; then echo "zypper"
    else echo ""; fi
}

distro_name() {
    local id="" name=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        id="${ID:-}"
        name="${PRETTY_NAME:-${ID:-linux}}"
    fi
    printf '%s' "${name:-linux} (${id:-unknown})"
}

# ----------------------------------------------------------------------------
# Dependency tables
# ----------------------------------------------------------------------------
deps_for() {
    case "$1" in
        apt)
            # Debian / Ubuntu / Mint / Pop!_OS
            echo "build-essential gcc g++ make git diffstat chrpath cpio file gawk wget curl
                  python3 python3-pip python3-venv python3-git python3-jinja2
                  xz-utils zstd unzip texinfo bzip2 fdisk rsync socat
                  libsdl1.2-dev libssl-dev libelf-dev rpcsvc-proto locales"
            ;;
        dnf|yum)
            # Fedora / RHEL / CentOS Stream / Rocky / Alma
            echo "gcc gcc-c++ make git diffstat chrpath cpio file gawk wget curl
                  python3 python3-pip python3-devel python3-GitPython python3-jinja2
                  xz zstd unzip texinfo bzip2 rsync socat
                  SDL2-devel openssl-devel libselinux-devel rpcgen
                  perl-Data-Dumper perl-Text-ParseWords perl-Thread-Queue"
            ;;
        pacman)
            # Arch / Manjaro / EndeavourOS
            echo "base-devel gcc git diffstat chrpath cpio file gawk wget curl
                  python python-pip python-gitpython python-jinja
                  xz zstd unzip texinfo bzip2 rsync socat
                  sdl2 openssl rsync"
            ;;
        zypper)
            # openSUSE / SLES
            echo "gcc gcc-c++ make git diffstat chrpath cpio file gawk wget curl
                  python3 python3-pip python3-devel python3-git python3-Jinja2
                  xz zstd unzip texinfo bzip2 rsync socat
                  libSDL2-devel libopenssl-devel libelf-devel rpcgen"
            ;;
        *) echo "" ;;
    esac
}

# ----------------------------------------------------------------------------
# Checks
# ----------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

check_disk_space() {
    local path="$1" avail_kb avail_gb
    mkdir -p "${path}"
    avail_kb=$(df -Pk "${path}" | awk 'NR==2 {print $4}')
    avail_gb=$(( avail_kb / 1024 / 1024 ))
    if (( avail_gb < MIN_DISK_GB )); then
        warn "Only ${avail_gb} GB free at ${path}. A Yocto build needs ${MIN_DISK_GB} GB+ (100 GB+ recommended)."
        if (( ASSUME_YES == 0 )); then
            local reply
            read -r -p "Continue anyway? (y/N): " reply
            [[ "${reply,,}" == y* ]] || die "Aborted due to insufficient disk space."
        fi
    else
        ok "Disk space: ${avail_gb} GB available at ${path}"
    fi
}

check_posix_shell() {
    local target
    if [[ -L /bin/sh ]]; then
        target="$(readlink -f /bin/sh)"
    else
        target="/bin/sh"
    fi
    case "${target##*/}" in
        bash|dash|ksh|mksh) ok "/bin/sh -> ${target}" ;;
        *) warn "/bin/sh points to '${target}'. Yocto requires bash or dash."
           warn "Fix with: sudo ln -sf bash /bin/sh   (Arch/Fedora users)" ;;
    esac
}

check_unshare() {
    if have unshare; then
        ok "unshare available (BitBake network isolation)"
    else
        warn "'unshare' not found; some BitBake recipes rely on it (util-linux package)."
    fi
}

check_utf8_locale() {
    if locale 2>/dev/null | grep -qi 'UTF-8'; then
        ok "UTF-8 locale active"
    else
        warn "No UTF-8 locale detected. Yocto requires one, e.g. 'export LANG=en_US.UTF-8'."
    fi
}

# ----------------------------------------------------------------------------
# Sudo shim (never silently escalates)
# ----------------------------------------------------------------------------
SUDO=""
setup_sudo() {
    if [[ ${EUID} -eq 0 ]]; then
        SUDO=""
    elif have sudo; then
        SUDO="sudo"
    else
        die "sudo not found and not running as root; cannot install packages. Use --no-deps."
    fi
}

confirm_deps() {
    local pm="$1"; shift
    local pkgs="$*"
    if (( ASSUME_YES == 0 )); then
        info "The following host packages will be installed via ${pm}:"
        printf '    %s\n' ${pkgs}
        local reply
        read -r -p "Proceed? (Y/n): " reply
        [[ "${reply,,}" == n* ]] && { warn "Skipping package installation (--no-deps behaviour)."; return 1; }
    fi
    return 0
}

install_deps() {
    local pm
    pm="$(detect_pkg_manager)"
    if [[ ${INSTALL_DEPS} -eq 0 ]]; then
        warn "Skipping system dependency installation (--no-deps)."
        return 0
    fi
    if [[ -z "${pm}" ]]; then
        warn "Could not detect a supported package manager."
        warn "Install the Yocto host packages manually (see README Section 5)."
        return 0
    fi

    local pkgs
    pkgs="$(deps_for "${pm}")"
    [[ -n "${pkgs}" ]] || { warn "No package list for '${pm}'; skipping."; return 0; }

    confirm_deps "${pm}" ${pkgs} || return 0
    setup_sudo
    info "Installing host toolchain via ${pm}..."

    case "${pm}" in
        apt)
            ${SUDO} env DEBIAN_FRONTEND=noninteractive apt-get update -qq
            # python3-venv/python3-git names vary on very old releases; tolerate misses.
            # shellcheck disable=SC2086
            ${SUDO} env DEBIAN_FRONTEND=noninteractive \
                apt-get install -y --no-install-recommends ${pkgs} \
                || ${SUDO} env DEBIAN_FRONTEND=noninteractive apt-get install -y ${pkgs}
            ;;
        dnf|yum)
            ${SUDO} ${pm} install -y ${pkgs} ;;
        pacman)
            ${SUDO} pacman -Sy --needed --noconfirm ${pkgs} ;;
        zypper)
            ${SUDO} zypper --non-interactive install ${pkgs} ;;
    esac
    ok "Host toolchain installed."
}

# ----------------------------------------------------------------------------
# Repository acquisition
# ----------------------------------------------------------------------------
fetch_repo() {
    local dir="$1" url="$2" ref="$3"

    if [[ -d "${dir}/.git" ]]; then
        info "Existing checkout found at ${dir}; updating..."
        git -C "${dir}" fetch --depth 1 origin "${ref}"
        git -C "${dir}" checkout -q "${ref}"
        git -C "${dir}" reset -q --hard "origin/${ref}" 2>/dev/null || true
        ok "Repository updated to ${ref}."
        return 0
    fi

    if [[ -e "${dir}" ]]; then
        die "${dir} exists but is not a git checkout. Move it aside or use --dir."
    fi

    info "Cloning ${url} (${ref}) into ${dir}..."
    mkdir -p "$(dirname "${dir}")"
    if git clone --depth 1 --branch "${ref}" "${url}" "${dir}" 2>/dev/null; then
        ok "Repository cloned."
    else
        warn "Ref '${ref}' not found as a branch; retrying then trying default branch..."
        git clone --depth 1 "${url}" "${dir}"
        git -C "${dir}" fetch --depth 1 origin "${ref}" 2>/dev/null || true
        git -C "${dir}" checkout -q "${ref}" 2>/dev/null || warn "Could not checkout '${ref}'; left on default branch."
        ok "Repository cloned (default branch)."
    fi
}

# ----------------------------------------------------------------------------
# Python virtualenv + bitbake-setup
# ----------------------------------------------------------------------------
setup_venv() {
    local dir="$1" venv="$2"

    if [[ ! -d "${venv}" ]]; then
        info "Creating Python virtualenv at ${venv}..."
        python3 -m venv "${venv}" || die "Failed to create venv. On Debian/Ubuntu install 'python3-venv'."
        ok "Virtualenv created."
    else
        ok "Reusing existing virtualenv at ${venv}."
    fi

    # shellcheck disable=SC1091
    # shellcheck disable=SC1090
    local py="${venv}/bin/python"
    "${py}" -m pip install --quiet --upgrade pip setuptools wheel

    info "Installing bitbake-setup into the virtualenv..."
    if "${py}" -m pip install --quiet bitbake-setup; then
        ok "bitbake-setup installed."
    else
        warn "Could not install bitbake-setup from PyPI."
        if [[ -f "${dir}/bitbake/bin/bitbake-setup" ]]; then
            ok "Falling back to in-tree bitbake from the layer checkout."
        else
            warn "bitbake-setup unavailable. You can still use the manual workflow (README section 4)."
        fi
    fi
}

activate_hint() {
    printf '\n%s%s%s\n' "${C_BOLD}" "To use bitbake-setup in this shell:" "${C_RESET}"
    printf '    source %s/bin/activate\n' "${VENV_DIR}"
}

# ----------------------------------------------------------------------------
# Hand-off
# ----------------------------------------------------------------------------
run_diagnostics() {
    banner
    info "Distro:        $(distro_name)"
    info "Package mgr:   $(detect_pkg_manager || true)"
    info "Install dir:   ${INSTALL_DIR}"
    info "Virtualenv:    ${VENV_DIR}"
    info "Repo:          ${REPO_URL} @ ${REPO_REF}"
    echo
    check_disk_space "$(dirname "${INSTALL_DIR}")" || true
    check_posix_shell
    check_unshare
    check_utf8_locale
    if have python3; then ok "python3: $(python3 --version 2>&1)"; else warn "python3 not found"; fi
    if have git;     then ok "git: $(git --version 2>&1)";         else warn "git not found"; fi
}

configure() {
    local dir="$1"
    if [[ ${RUN_CONFIGURE} -eq 0 ]]; then
        ok "Bootstrap complete. Skipped configuration (--no-configure)."
        printf '\nRun the configuration wizard with:\n    python3 %s/scripts/setup-chip.py\n' "${dir}"
        return 0
    fi

    local extra=()
    if (( SETUP_INIT_HANDOFF == 1 )); then
        extra+=(--init)
    fi

    local script="${dir}/scripts/setup-chip.py"
    [[ -f "${script}" ]] || die "Configuration script not found: ${script}"

    echo
    info "Starting the configuration wizard..."
    printf '%s\n' "------------------------------------------------------------"

    if [[ -t 0 ]]; then
        exec python3 "${script}" ${extra[@]+"${extra[@]}"} ${FORWARD_ARGS[@]+"${FORWARD_ARGS[@]}"}
    else
        # No TTY (e.g. piped through sudo / CI): defer the wizard to an interactive run.
        warn "No TTY detected; the interactive wizard needs a terminal to prompt."
        warn "Steps above are complete. Then run:"
        printf '    python3 %s\n' "${script}"
        return 0
    fi
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
main() {
    require_linux
    require_non_root

    if (( CHECK_ONLY == 1 )); then
        run_diagnostics
        exit 0
    fi

    banner
    info "Distro:      $(distro_name)"
    info "Install dir: ${INSTALL_DIR}"
    info "Venv:        ${VENV_DIR}"

    have git     || die "git is required. Install it and re-run (or use --check)."
    have python3 || die "python3 is required. Install it and re-run (or use --check)."

    check_disk_space "$(dirname "${INSTALL_DIR}")"
    check_posix_shell
    check_unshare
    check_utf8_locale

    install_deps
    fetch_repo "${INSTALL_DIR}" "${REPO_URL}" "${REPO_REF}"
    setup_venv "${INSTALL_DIR}" "${VENV_DIR}"

    chmod +x "${INSTALL_DIR}/scripts/"*.sh "${INSTALL_DIR}/scripts/"*.py 2>/dev/null || true

    ok "All files are in place at ${INSTALL_DIR}"
    activate_hint
    configure "${INSTALL_DIR}"
}

main "$@"
