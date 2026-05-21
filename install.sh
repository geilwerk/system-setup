#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
LOG_STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-system-setup"
LOG_FILE="$LOG_DIR/install-$LOG_STAMP.log"

NVM_VERSION="${NVM_VERSION:-0.40.3}"
MINICONDA_PREFIX="${MINICONDA_PREFIX:-$HOME/miniconda3}"
KANATA_REPO="${KANATA_REPO:-https://github.com/nanocyte/kanata-kde}"
KANATA_SRC_DIR="${KANATA_SRC_DIR:-$HOME/.local/src/kanata-kde}"
KANATA_CONFIG_DIR="${KANATA_CONFIG_DIR:-$HOME/.config/kanata}"
COPYOUS_UUID="copyous@boerdereinar.dev"

DRY_RUN=0
NO_TUI=0
ASSUME_YES=0
ONLY_TASKS=""
LOG_READY=0

declare -A SELECTED=()
APT_UPDATED=0

TASK_ORDER=(
  base
  rust
  node_nvm
  conda_miniconda
  kanata
  ollama
  codex
  claude_code
  flatpak
  extension_manager
  copyous
  google_chrome
  vscode
  pandoc
  gh
  docker_engine
  docker_desktop
  telegram
)

DEFAULT_TASKS=("${TASK_ORDER[@]}")

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --dry-run              Show the selected tasks without installing anything.
  --no-tui               Use defaults without showing checkbox menus.
  --only a,b,c           Run only the comma-separated task ids.
  --yes                  Do not ask final confirmation questions.
  --list                 List available task ids.
  -h, --help             Show this help.

Environment:
  NVM_VERSION=0.40.3
  MINICONDA_PREFIX=$HOME/miniconda3
  KANATA_REPO=https://github.com/nanocyte/kanata-kde
  ALLOW_UNSUPPORTED_DOCKER_DESKTOP=1
EOF
}

list_tasks() {
  cat <<'EOF'
base                 Core apt packages: curl, git, build-essential, gpg, etc.
rust                 Rustup stable toolchain.
node_nvm             nvm plus latest Node LTS.
conda_miniconda      Miniconda user install for conda.
kanata               Kanata via cargo, config clone, uinput, user service.
ollama               Ollama official install script.
codex                OpenAI Codex CLI via npm.
claude_code          Claude Code native installer.
flatpak              Flatpak, Flathub, GNOME Software plugin.
extension_manager    GNOME Extension Manager from Flathub.
copyous              Copyous GNOME Shell extension.
google_chrome        Google Chrome stable deb.
vscode               Visual Studio Code Microsoft apt repository.
pandoc               Pandoc from Ubuntu apt.
gh                   GitHub CLI official apt repository.
docker_engine        Docker Engine official apt repository.
docker_desktop       Docker Desktop deb, supported on Ubuntu 26.04/24.04.
telegram             Telegram Desktop from Flathub.
EOF
}

log() {
  printf '\n\033[1;34m==>\033[0m %s\n' "$*"
  if (( LOG_READY )); then
    printf '\n==> %s\n' "$*" >> "$LOG_FILE"
  fi
}

warn() {
  printf '\n\033[1;33mWARN:\033[0m %s\n' "$*" >&2
  if (( LOG_READY )); then
    printf '\nWARN: %s\n' "$*" >> "$LOG_FILE"
  fi
}

die() {
  printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2
  if (( LOG_READY )); then
    printf '\nERROR: %s\n' "$*" >> "$LOG_FILE"
  fi
  exit 1
}

run() {
  log "$*"
  if (( DRY_RUN )); then
    return 0
  fi
  "$@"
}

run_bash() {
  log "$*"
  if (( DRY_RUN )); then
    return 0
  fi
  bash -lc "$*"
}

require_regular_user() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    die "Run this as your normal desktop user, not with sudo. The script will ask sudo for system changes."
  fi
}

ensure_log_dir() {
  if mkdir -p "$LOG_DIR" 2>/dev/null; then
    return
  fi

  warn "Could not create $LOG_DIR; falling back to /tmp for this run."
  LOG_DIR="/tmp/ubuntu-system-setup-${USER:-user}"
  LOG_FILE="$LOG_DIR/install-$LOG_STAMP.log"
  mkdir -p "$LOG_DIR"
}

start_logging() {
  ensure_log_dir
  : > "$LOG_FILE"
  LOG_READY=1
  log "Logging command plan to $LOG_FILE"
}

parse_args() {
  while (($#)); do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --no-tui)
        NO_TUI=1
        ;;
      --only)
        shift
        [[ $# -gt 0 ]] || die "--only requires a comma-separated task list"
        ONLY_TASKS="$1"
        NO_TUI=1
        ;;
      --only=*)
        ONLY_TASKS="${1#*=}"
        NO_TUI=1
        ;;
      --yes|-y)
        ASSUME_YES=1
        ;;
      --list)
        list_tasks
        exit 0
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
    shift
  done
}

select_task() {
  SELECTED["$1"]=1
}

is_selected() {
  [[ -n "${SELECTED[$1]:-}" ]]
}

select_defaults() {
  SELECTED=()
  local task
  for task in "${DEFAULT_TASKS[@]}"; do
    select_task "$task"
  done
}

select_only_tasks() {
  SELECTED=()
  local task
  IFS=',' read -r -a tasks <<< "$ONLY_TASKS"
  for task in "${tasks[@]}"; do
    task="${task//[[:space:]]/}"
    [[ -n "$task" ]] || continue
    select_task "$task"
  done
}

bootstrap_tui_tools() {
  if (( DRY_RUN )) || (( NO_TUI )) || command -v whiptail >/dev/null 2>&1; then
    return
  fi

  log "Installing minimal TUI bootstrap packages: curl, ca-certificates, whiptail"
  sudo -v
  sudo apt-get update
  sudo apt-get install -y curl ca-certificates whiptail
}

select_category() {
  local title="$1"
  local message="$2"
  shift 2

  local output
  output="$(whiptail \
    --title "$title" \
    --separate-output \
    --checklist "$message" \
    22 94 12 \
    "$@" \
    3>&1 1>&2 2>&3)" || die "Installer cancelled."

  local task
  while IFS= read -r task; do
    [[ -n "$task" ]] && select_task "$task"
  done <<< "$output"
}

select_with_tui() {
  if (( NO_TUI )) || [[ ! -t 0 ]] || [[ ! -t 1 ]] || ! command -v whiptail >/dev/null 2>&1; then
    select_defaults
    return
  fi

  SELECTED=()
  select_category \
    "Ubuntu Setup: Core" \
    "Space toggles. Enter confirms this group." \
    "base" "Core apt packages: curl, git, build-essential, gpg, jq" ON \
    "rust" "Rustup stable toolchain" ON \
    "node_nvm" "nvm plus latest Node LTS" ON \
    "conda_miniconda" "Miniconda user install for conda" ON \
    "pandoc" "Pandoc from Ubuntu apt" ON

  select_category \
    "Ubuntu Setup: Keyboard" \
    "Kanata needs Rust/cargo and a logout after group changes." \
    "kanata" "Kanata via cargo, config clone, uinput, user service" ON

  select_category \
    "Ubuntu Setup: AI CLIs" \
    "Codex expects npm. Claude Code uses Anthropic's native installer." \
    "ollama" "Ollama official install script" ON \
    "codex" "OpenAI Codex CLI via npm" ON \
    "claude_code" "Claude Code native installer" ON

  select_category \
    "Ubuntu Setup: Desktop Apps" \
    "Flatpak/Flathub is used where it is the cleanest non-Snap route." \
    "flatpak" "Flatpak, Flathub, GNOME Software plugin" ON \
    "extension_manager" "GNOME Extension Manager from Flathub" ON \
    "copyous" "Copyous GNOME Shell extension" ON \
    "google_chrome" "Google Chrome stable deb" ON \
    "vscode" "Visual Studio Code apt repository" ON \
    "telegram" "Telegram Desktop from Flathub" ON

  select_category \
    "Ubuntu Setup: Containers and GitHub" \
    "Docker Desktop is skipped on unsupported Ubuntu releases unless explicitly allowed." \
    "gh" "GitHub CLI official apt repository" ON \
    "docker_engine" "Docker Engine official apt repository" ON \
    "docker_desktop" "Docker Desktop deb" ON
}

selected_tasks_string() {
  local task
  local selected=()
  for task in "${TASK_ORDER[@]}"; do
    if is_selected "$task"; then
      selected+=("$task")
    fi
  done
  printf '%s\n' "${selected[@]}"
}

task_exists() {
  local needle="$1"
  local task
  for task in "${TASK_ORDER[@]}"; do
    [[ "$task" == "$needle" ]] && return 0
  done
  return 1
}

validate_selected_tasks() {
  local task
  for task in "${!SELECTED[@]}"; do
    task_exists "$task" || die "Unknown task id: $task. Use --list to see available tasks."
  done
}

confirm_selection() {
  local selected
  selected="$(selected_tasks_string)"

  printf '\nSelected tasks:\n%s\n' "$selected"

  if (( DRY_RUN )) || (( ASSUME_YES )); then
    return
  fi

  if command -v whiptail >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
    whiptail --title "Confirm Install" --yesno "Run the selected setup tasks now?" 10 72 || die "Installer cancelled."
  else
    read -r -p "Run the selected setup tasks now? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || die "Installer cancelled."
  fi
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

dependency_warnings() {
  local warnings=()

  if is_selected kanata && ! is_selected rust && ! has_command cargo; then
    warnings+=("Kanata is selected, but Rust is not and cargo was not found. Kanata install will fail unless cargo is already available.")
  fi
  if is_selected codex && ! is_selected node_nvm && ! has_command npm; then
    warnings+=("Codex is selected, but Node/nvm is not and npm was not found. Codex install will fail unless npm is already available.")
  fi
  if is_selected extension_manager && ! is_selected flatpak && ! has_command flatpak; then
    warnings+=("Extension Manager is selected, but Flatpak is not and flatpak was not found.")
  fi
  if is_selected telegram && ! is_selected flatpak && ! has_command flatpak; then
    warnings+=("Telegram is selected, but Flatpak is not and flatpak was not found.")
  fi

  if ((${#warnings[@]} == 0)); then
    return
  fi

  printf '\nDependency warnings:\n'
  printf -- '- %s\n' "${warnings[@]}"

  if (( ASSUME_YES )) || (( DRY_RUN )); then
    return
  fi

  if command -v whiptail >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
    local message
    message="$(printf '%s\n' "${warnings[@]}")"
    whiptail --title "Dependency Warning" --yesno "$message\n\nContinue anyway?" 16 86 || die "Installer cancelled."
  else
    read -r -p "Continue anyway? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || die "Installer cancelled."
  fi
}

load_os_release() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
  else
    ID="unknown"
    VERSION_ID="unknown"
    VERSION_CODENAME="unknown"
  fi

  OS_ID="${ID:-unknown}"
  OS_VERSION_ID="${VERSION_ID:-unknown}"
  OS_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-unknown}}"

  if [[ "$OS_ID" != "ubuntu" ]]; then
    warn "This script is tuned for Ubuntu, but detected $OS_ID $OS_VERSION_ID."
  fi
}

apt_update_once() {
  if (( APT_UPDATED )); then
    return
  fi
  run sudo apt-get update
  APT_UPDATED=1
}

apt_install() {
  apt_update_once
  run sudo apt-get install -y "$@"
}

apt_install_optional() {
  apt_update_once
  log "sudo apt-get install -y $*"
  if (( DRY_RUN )); then
    return
  fi
  if ! sudo apt-get install -y "$@"; then
    warn "Optional apt install failed: $*"
  fi
}

apt_install_optional_each() {
  local pkg
  apt_update_once
  for pkg in "$@"; do
    log "sudo apt-get install -y $pkg"
    if (( DRY_RUN )); then
      continue
    fi
    if ! sudo apt-get install -y "$pkg"; then
      warn "Optional apt install failed: $pkg"
    fi
  done
}

install_with_backup() {
  local src="$1"
  local dest="$2"
  local mode="${3:-0644}"

  if [[ -f "$dest" ]] && ! cmp -s "$src" "$dest"; then
    local backup="${dest}.bak.$(date +%Y%m%d-%H%M%S)"
    run cp "$dest" "$backup"
    warn "Existing $dest differed; backed it up to $backup"
  fi

  run install -D -m "$mode" "$src" "$dest"
}

install_base() {
  apt_install \
    apt-transport-https \
    build-essential \
    ca-certificates \
    curl \
    git \
    gnome-terminal \
    gnupg \
    jq \
    libssl-dev \
    libudev-dev \
    lsb-release \
    pkg-config \
    python3 \
    python3-venv \
    software-properties-common \
    tar \
    unzip \
    wget \
    whiptail \
    xz-utils
}

source_cargo_env() {
  if [[ -r "$HOME/.cargo/env" ]]; then
    # shellcheck source=/dev/null
    . "$HOME/.cargo/env"
  fi
  export PATH="$HOME/.cargo/bin:$PATH"
}

install_rust() {
  if ! has_command rustup; then
    run_bash "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
  else
    log "rustup is already installed."
  fi

  source_cargo_env
  run rustup default stable
  run rustup update stable
}

source_nvm() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"
  fi
}

install_node_nvm() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    run_bash "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$NVM_VERSION/install.sh | bash"
  else
    log "nvm is already installed at $NVM_DIR."
  fi

  source_nvm
  has_command nvm || die "nvm did not load. Try opening a new shell, then rerun the node_nvm task."

  run nvm install --lts
  run nvm alias default 'lts/*'
  run nvm use default

  if has_command corepack; then
    run corepack enable
  else
    warn "corepack was not found after Node install."
  fi
}

miniconda_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      printf 'x86_64'
      ;;
    aarch64|arm64)
      printf 'aarch64'
      ;;
    *)
      return 1
      ;;
  esac
}

install_conda_miniconda() {
  if has_command conda; then
    log "conda is already installed at $(command -v conda)."
    return
  fi

  if [[ -x "$MINICONDA_PREFIX/bin/conda" ]]; then
    log "Miniconda already exists at $MINICONDA_PREFIX."
    run "$MINICONDA_PREFIX/bin/conda" init --all
    run "$MINICONDA_PREFIX/bin/conda" config --set auto_activate_base false
    return
  fi

  local arch installer
  arch="$(miniconda_arch)" || die "Unsupported Miniconda architecture: $(uname -m)"
  installer="$(mktemp --suffix=.sh)"

  run curl -fsSLo "$installer" "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${arch}.sh"
  run bash "$installer" -b -p "$MINICONDA_PREFIX"
  rm -f "$installer"

  run "$MINICONDA_PREFIX/bin/conda" init --all
  run "$MINICONDA_PREFIX/bin/conda" config --set auto_activate_base false

  warn "Conda shell initialization requires opening a new terminal, or sourcing your shell rc file."
}

ensure_cargo_for_current_shell() {
  source_cargo_env
  has_command cargo || die "cargo was not found. Select the rust task or install Rust first."
}

install_kanata() {
  ensure_cargo_for_current_shell
  if ! has_command kanata; then
    run cargo install kanata
  else
    log "kanata is already installed at $(command -v kanata)."
  fi

  run mkdir -p "$(dirname "$KANATA_SRC_DIR")"
  if [[ -d "$KANATA_SRC_DIR/.git" ]]; then
    run git -C "$KANATA_SRC_DIR" pull --ff-only
  else
    run git clone "$KANATA_REPO" "$KANATA_SRC_DIR"
  fi

  install_with_backup "$KANATA_SRC_DIR/kanata.kbd" "$KANATA_CONFIG_DIR/kanata.kbd" 0644

  run sudo groupadd -f input
  run sudo groupadd -f uinput
  run sudo usermod -aG input "$USER"
  run sudo usermod -aG uinput "$USER"

  local udev_tmp
  udev_tmp="$(mktemp)"
  printf '%s\n' 'KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"' > "$udev_tmp"
  install_with_backup "$udev_tmp" "/tmp/99-kanata-uinput.rules" 0644
  run sudo install -D -m 0644 "/tmp/99-kanata-uinput.rules" "/etc/udev/rules.d/99-kanata-uinput.rules"
  rm -f "$udev_tmp" /tmp/99-kanata-uinput.rules

  local module_tmp
  module_tmp="$(mktemp)"
  printf '%s\n' 'uinput' > "$module_tmp"
  install_with_backup "$module_tmp" "/tmp/uinput.conf" 0644
  run sudo install -D -m 0644 "/tmp/uinput.conf" "/etc/modules-load.d/uinput.conf"
  rm -f "$module_tmp" /tmp/uinput.conf

  run sudo modprobe uinput
  run sudo udevadm control --reload-rules
  run sudo udevadm trigger

  install_with_backup "$SCRIPT_DIR/services/user/kanata.service" "$HOME/.config/systemd/user/kanata.service" 0644
  run systemctl --user daemon-reload
  run systemctl --user enable kanata.service

  warn "Kanata group changes require logging out and back in. The user service is enabled but not started automatically in this session."
}

install_ollama() {
  if has_command ollama; then
    log "ollama is already installed at $(command -v ollama)."
    return
  fi
  run_bash "curl -fsSL https://ollama.com/install.sh | sh"
}

ensure_npm_for_current_shell() {
  source_nvm
  if ! has_command npm; then
    die "npm was not found. Select node_nvm or install Node/npm before Codex."
  fi
}

install_codex() {
  ensure_npm_for_current_shell
  run npm install -g @openai/codex
}

install_claude_code() {
  if has_command claude; then
    log "claude is already installed at $(command -v claude)."
    return
  fi
  run_bash "curl -fsSL https://claude.ai/install.sh | bash"
}

install_flatpak() {
  apt_install flatpak gnome-software gnome-software-plugin-flatpak
  run sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  warn "Flatpak/Flathub may need a logout or reboot before GNOME Software shows Flathub apps."
}

ensure_flatpak_available() {
  has_command flatpak || die "flatpak was not found. Select the flatpak task first."
}

install_extension_manager() {
  ensure_flatpak_available
  run flatpak install -y flathub com.mattjakeman.ExtensionManager
}

install_copyous() {
  apt_install_optional_each \
    gnome-shell-common \
    gnome-browser-connector \
    gir1.2-gda-6.0 \
    gir1.2-gsound-1.0 \
    libgda-6.0-6 \
    libgsound0 \
    unzip

  if ! has_command gnome-extensions; then
    warn "gnome-extensions command was not found. Install Copyous manually from Extension Manager."
    return
  fi

  if ! has_command gnome-shell; then
    warn "gnome-shell command was not found. Install Copyous manually once GNOME is available."
    return
  fi

  local shell_version shell_major info_url json download_url zip_path
  shell_version="$(gnome-shell --version | awk '{print $3}')"
  shell_major="${shell_version%%.*}"
  info_url="https://extensions.gnome.org/extension-info/?uuid=copyous%40boerdereinar.dev&shell_version=$shell_major"

  log "Looking up Copyous for GNOME Shell $shell_version"
  if (( DRY_RUN )); then
    return
  fi

  json="$(curl -fsSL "$info_url")" || {
    warn "Could not fetch Copyous metadata from extensions.gnome.org."
    return
  }
  download_url="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("download_url",""))')" || download_url=""

  if [[ -z "$download_url" || "$download_url" == "null" ]]; then
    warn "Copyous does not report a compatible download for GNOME Shell $shell_major."
    return
  fi

  zip_path="$(mktemp --suffix=.zip)"
  curl -fsSL "https://extensions.gnome.org${download_url}" -o "$zip_path"
  gnome-extensions install --force "$zip_path" || {
    rm -f "$zip_path"
    warn "Copyous zip download succeeded, but gnome-extensions install failed."
    return
  }
  rm -f "$zip_path"

  if ! gnome-extensions enable "$COPYOUS_UUID"; then
    warn "Copyous installed, but enabling it failed. Log out/in, then enable it in Extension Manager."
  fi
}

install_google_chrome() {
  local arch
  arch="$(dpkg --print-architecture)"
  if [[ "$arch" != "amd64" ]]; then
    warn "Google Chrome stable deb is amd64-only in this installer. Detected $arch; skipping."
    return
  fi

  local deb
  deb="$(mktemp --suffix=.deb)"
  run curl -fsSLo "$deb" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  run sudo apt-get install -y "$deb"
  rm -f "$deb"
}

install_vscode() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  run curl -fsSLo "$tmpdir/microsoft.asc" https://packages.microsoft.com/keys/microsoft.asc
  run gpg --dearmor -o "$tmpdir/microsoft.gpg" "$tmpdir/microsoft.asc"
  run sudo install -D -m 0644 "$tmpdir/microsoft.gpg" /usr/share/keyrings/microsoft.gpg

  cat > "$tmpdir/vscode.sources" <<'EOF'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
  run sudo install -D -m 0644 "$tmpdir/vscode.sources" /etc/apt/sources.list.d/vscode.sources
  rm -rf "$tmpdir"

  run sudo apt-get update
  APT_UPDATED=1
  run sudo apt-get install -y code
}

install_pandoc() {
  apt_install pandoc
}

install_gh() {
  local tmpdir arch
  tmpdir="$(mktemp -d)"
  arch="$(dpkg --print-architecture)"

  run sudo install -m 0755 -d /etc/apt/keyrings
  run wget -nv -O "$tmpdir/githubcli-archive-keyring.gpg" https://cli.github.com/packages/githubcli-archive-keyring.gpg
  run sudo install -m 0644 "$tmpdir/githubcli-archive-keyring.gpg" /etc/apt/keyrings/githubcli-archive-keyring.gpg
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' "$arch" > "$tmpdir/github-cli.list"
  run sudo install -D -m 0644 "$tmpdir/github-cli.list" /etc/apt/sources.list.d/github-cli.list
  rm -rf "$tmpdir"

  run sudo apt-get update
  APT_UPDATED=1
  run sudo apt-get install -y gh
}

setup_docker_repo() {
  local tmpdir arch
  tmpdir="$(mktemp -d)"
  arch="$(dpkg --print-architecture)"

  [[ "$OS_CODENAME" != "unknown" ]] || die "Could not determine Ubuntu codename for Docker repository."

  run sudo install -m 0755 -d /etc/apt/keyrings
  run curl -fsSLo "$tmpdir/docker.asc" https://download.docker.com/linux/ubuntu/gpg
  run sudo install -m 0644 "$tmpdir/docker.asc" /etc/apt/keyrings/docker.asc
  run sudo chmod a+r /etc/apt/keyrings/docker.asc

  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' "$arch" "$OS_CODENAME" > "$tmpdir/docker.list"
  run sudo install -D -m 0644 "$tmpdir/docker.list" /etc/apt/sources.list.d/docker.list
  rm -rf "$tmpdir"

  run sudo apt-get update
  APT_UPDATED=1
}

install_docker_engine() {
  setup_docker_repo
  run sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  run sudo usermod -aG docker "$USER"
  warn "Docker group changes require logging out and back in."
}

install_docker_desktop() {
  local arch deb
  arch="$(dpkg --print-architecture)"

  if [[ "$arch" != "amd64" ]]; then
    warn "Docker Desktop deb is amd64-only in this installer. Detected $arch; skipping."
    return
  fi

  if [[ "$OS_VERSION_ID" != "26.04" && "$OS_VERSION_ID" != "24.04" && "${ALLOW_UNSUPPORTED_DOCKER_DESKTOP:-0}" != "1" ]]; then
    warn "Docker Desktop official docs list Ubuntu 26.04 and 24.04 support. Detected $OS_VERSION_ID; skipping. Set ALLOW_UNSUPPORTED_DOCKER_DESKTOP=1 to try anyway."
    return
  fi

  setup_docker_repo
  apt_install gnome-terminal

  deb="$(mktemp --suffix=.deb)"
  run curl -fsSLo "$deb" https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb
  run sudo apt-get install -y "$deb"
  rm -f "$deb"
}

install_telegram() {
  ensure_flatpak_available
  run flatpak install -y flathub org.telegram.desktop
}

run_task() {
  local task="$1"
  case "$task" in
    base) install_base ;;
    rust) install_rust ;;
    node_nvm) install_node_nvm ;;
    conda_miniconda) install_conda_miniconda ;;
    kanata) install_kanata ;;
    ollama) install_ollama ;;
    codex) install_codex ;;
    claude_code) install_claude_code ;;
    flatpak) install_flatpak ;;
    extension_manager) install_extension_manager ;;
    copyous) install_copyous ;;
    google_chrome) install_google_chrome ;;
    vscode) install_vscode ;;
    pandoc) install_pandoc ;;
    gh) install_gh ;;
    docker_engine) install_docker_engine ;;
    docker_desktop) install_docker_desktop ;;
    telegram) install_telegram ;;
    *) die "Unknown task id: $task" ;;
  esac
}

run_selected_tasks() {
  local task
  for task in "${TASK_ORDER[@]}"; do
    if is_selected "$task"; then
      log "Starting task: $task"
      run_task "$task"
    fi
  done
}

post_install_notes() {
  cat <<'EOF'

Post-install notes:
- Log out and back in for Kanata uinput/input group membership.
- Log out and back in for Docker group membership.
- Reboot or log out/in if GNOME Software does not show Flathub apps yet.
- Open a new terminal for conda initialization to take effect.
- Start Docker Desktop from the app launcher the first time so it can finish its own setup.
- Letta code is intentionally not included here; use the separate installer script.
EOF
}

main() {
  parse_args "$@"
  require_regular_user
  load_os_release

  if [[ -n "$ONLY_TASKS" ]]; then
    select_only_tasks
  else
    bootstrap_tui_tools
    select_with_tui
  fi

  validate_selected_tasks
  dependency_warnings
  confirm_selection

  if (( DRY_RUN )); then
    log "Dry run complete. No install commands were executed."
    return
  fi

  start_logging

  sudo -v
  run_selected_tasks
  post_install_notes
}

main "$@"
