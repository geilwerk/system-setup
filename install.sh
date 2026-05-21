#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
LOG_STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ubuntu-system-setup"
LOG_FILE="$LOG_DIR/install-$LOG_STAMP.log"
APT_UPDATED_STAMP=""

NVM_VERSION="${NVM_VERSION:-0.40.3}"
MINICONDA_PREFIX="${MINICONDA_PREFIX:-$HOME/miniconda3}"
KANATA_SOURCE_FILE="${KANATA_SOURCE_FILE:-$SCRIPT_DIR/kanata-setup/kanata.kbd}"
KANATA_CONFIG_DIR="${KANATA_CONFIG_DIR:-$HOME/.config/kanata}"
KANATA_UINPUT_GROUP="${KANATA_UINPUT_GROUP:-uinput}"
COPYOUS_UUID="copyous@boerdereinar.dev"
DEFAULT_OLLAMA_MODELS="glm-5.1:cloud kimi-k2.6:cloud gemini-3-flash-preview:cloud minimax-m2.7:cloud mistral-large-3:675b-cloud gemma4:31b-cloud qwen3.5:397b-cloud"
OLLAMA_MODELS="${OLLAMA_MODELS-$DEFAULT_OLLAMA_MODELS}"
OLLAMA_STARTUP_DELAY_SECONDS="${OLLAMA_STARTUP_DELAY_SECONDS:-3}"
OLLAMA_STARTUP_WAIT_SECONDS="${OLLAMA_STARTUP_WAIT_SECONDS:-20}"
OPEN_WEBUI_CONTAINER="${OPEN_WEBUI_CONTAINER:-open-webui}"
OPEN_WEBUI_IMAGE="${OPEN_WEBUI_IMAGE:-ghcr.io/open-webui/open-webui:main}"
OPEN_WEBUI_GPU_IMAGE="${OPEN_WEBUI_GPU_IMAGE:-ghcr.io/open-webui/open-webui:cuda}"
OPEN_WEBUI_PORT="${OPEN_WEBUI_PORT:-3000}"

DRY_RUN=0
NO_TUI=0
ASSUME_YES=0
ONLY_TASKS=""
LOG_READY=0

declare -A SELECTED=()
declare -a FAILED_TASKS=()
declare -a FAILED_TASK_STATUSES=()
APT_UPDATED=0

TASK_ORDER=(
  base
  rust
  node_nvm
  uv
  conda_miniconda
  kanata
  gnome_disable_key_repeat
  ollama
  codex
  opencode
  claude_code
  flatpak
  extension_manager
  copyous
  google_chrome
  vscode
  pandoc
  gh
  docker_engine
  nvidia_container_toolkit
  docker_desktop
  docker_desktop_pass
  open_webui
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
  KANATA_SOURCE_FILE=./kanata-setup/kanata.kbd
  KANATA_UINPUT_GROUP=uinput
  OLLAMA_MODELS="glm-5.1:cloud kimi-k2.6:cloud ..."
  OLLAMA_STARTUP_DELAY_SECONDS=3
  OLLAMA_STARTUP_WAIT_SECONDS=20
  ALLOW_UNSUPPORTED_DOCKER_DESKTOP=1
  DOCKER_PASS_GPG_ID=<gpg-key-id>
  OPEN_WEBUI_PORT=3000
  OPEN_WEBUI_GPU=1
EOF
}

list_tasks() {
  cat <<'EOF'
base                 Core apt packages: curl, git, build-essential, gpg, etc.
rust                 Rustup stable toolchain.
node_nvm             nvm plus latest Node LTS.
uv                   Astral uv and uvx standalone installer.
conda_miniconda      Miniconda user install for conda.
kanata               Kanata via cargo, repo config, uinput/input permissions, user service.
gnome_disable_key_repeat  Disable GNOME repeat keys for Kanata.
ollama               Ollama official install script plus configured model pulls.
codex                OpenAI Codex CLI via npm.
opencode             OpenCode official install script.
claude_code          Claude Code native installer.
flatpak              Flatpak, Flathub, GNOME Software plugin.
extension_manager    GNOME Extension Manager from Flathub.
copyous              Copyous GNOME Shell extension.
google_chrome        Google Chrome stable deb.
vscode               Visual Studio Code Microsoft apt repository.
pandoc               Pandoc from Ubuntu apt.
gh                   GitHub CLI official apt repository.
docker_engine        Docker Engine official apt repository.
nvidia_container_toolkit  NVIDIA Container Toolkit for Docker GPU containers.
docker_desktop       Docker Desktop deb, supported on Ubuntu 26.04/24.04.
docker_desktop_pass  Install pass and optionally initialize Docker Desktop credentials.
open_webui           Open WebUI Docker container.
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
  local display
  printf -v display '%q ' "$@"
  log "${display% }"
  if (( DRY_RUN )); then
    return 0
  fi
  "$@"
}

run_optional() {
  local display
  printf -v display '%q ' "$@"
  log "${display% }"
  if (( DRY_RUN )); then
    return 0
  fi
  if ! "$@"; then
    warn "Optional command failed: $*"
  fi
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
  APT_UPDATED_STAMP="$LOG_DIR/apt-updated-$LOG_STAMP"
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
    "uv" "Astral uv and uvx standalone installer" ON \
    "conda_miniconda" "Miniconda user install for conda" ON \
    "pandoc" "Pandoc from Ubuntu apt" ON

  select_category \
    "Ubuntu Setup: Keyboard" \
    "Kanata needs Rust/cargo and a logout after group changes." \
    "kanata" "Kanata via cargo, repo config, uinput/input permissions, user service" ON

  select_category \
    "Ubuntu Setup: AI CLIs" \
    "Codex expects npm. Claude Code uses Anthropic's native installer." \
    "ollama" "Ollama official install script plus model pulls" ON \
    "codex" "OpenAI Codex CLI via npm" ON \
    "opencode" "OpenCode official install script" ON \
    "claude_code" "Claude Code native installer" ON

  select_category \
    "Ubuntu Setup: Settings" \
    "Small desktop settings that make the rest of the setup behave better." \
    "gnome_disable_key_repeat" "Disable GNOME repeat keys for Kanata" ON

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
    "Docker Desktop now includes KVM/pass helpers. Open WebUI needs Docker running." \
    "gh" "GitHub CLI official apt repository" ON \
    "docker_engine" "Docker Engine official apt repository" ON \
    "nvidia_container_toolkit" "NVIDIA Container Toolkit for Docker GPU containers" ON \
    "docker_desktop" "Docker Desktop deb plus KVM prerequisites" ON \
    "docker_desktop_pass" "Docker Desktop pass credential helper" ON \
    "open_webui" "Open WebUI Docker container" ON
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
  if is_selected nvidia_container_toolkit && ! is_selected docker_engine && ! has_command docker; then
    warnings+=("NVIDIA Container Toolkit is selected, but Docker is not selected and docker was not found.")
  fi
  if is_selected open_webui && ! is_selected docker_engine && ! is_selected docker_desktop && ! has_command docker; then
    warnings+=("Open WebUI is selected, but no Docker install task is selected and docker was not found.")
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
  if (( APT_UPDATED )) || [[ -n "$APT_UPDATED_STAMP" && -f "$APT_UPDATED_STAMP" ]]; then
    APT_UPDATED=1
    return
  fi
  run sudo apt-get update
  APT_UPDATED=1
  if [[ -n "$APT_UPDATED_STAMP" ]]; then
    : > "$APT_UPDATED_STAMP"
  fi
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

source_local_bin() {
  export PATH="$HOME/.local/bin:$PATH"
}

install_uv() {
  source_local_bin
  if ! has_command uv; then
    run_bash "curl -LsSf https://astral.sh/uv/install.sh | sh"
  else
    log "uv is already installed at $(command -v uv)."
  fi

  if (( DRY_RUN )); then
    return
  fi

  source_local_bin
  has_command uv || die "uv was not found after installation."
  run uv --version
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

  [[ -f "$KANATA_SOURCE_FILE" ]] || die "Kanata source config not found: $KANATA_SOURCE_FILE"
  install_with_backup "$KANATA_SOURCE_FILE" "$KANATA_CONFIG_DIR/kanata.kbd" 0644

  run sudo groupadd -f input
  run sudo groupadd -f uinput
  run sudo groupadd -f "$KANATA_UINPUT_GROUP"
  run sudo usermod -aG input "$USER"
  run sudo usermod -aG uinput "$USER"
  run sudo usermod -aG "$KANATA_UINPUT_GROUP" "$USER"

  local udev_tmp
  udev_tmp="$(mktemp)"
  printf 'KERNEL=="uinput", MODE="0660", GROUP="%s", OPTIONS+="static_node=uinput"\n' "$KANATA_UINPUT_GROUP" > "$udev_tmp"
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
  if ! has_command ollama; then
    run_bash "curl -fsSL https://ollama.com/install.sh | sh"
  else
    log "ollama is already installed at $(command -v ollama)."
  fi

  pull_ollama_models
}

pull_ollama_models() {
  local -a models
  local -a failed_models=()
  local model

  if [[ -z "${OLLAMA_MODELS//[[:space:]]/}" ]]; then
    log "No Ollama models configured for pulling."
    return
  fi

  if (( ! DRY_RUN )); then
    has_command ollama || die "ollama was not found after installation."
  fi

  if ! wait_for_ollama_server; then
    warn "Could not connect to the Ollama server after installation; skipping configured model pulls for now."
    warn "Once Ollama is running, rerun: ./install.sh --only ollama --yes"
    return 0
  fi

  local IFS=' '
  read -r -a models <<< "$OLLAMA_MODELS"

  for model in "${models[@]}"; do
    [[ -n "$model" ]] || continue
    if ! run ollama pull "$model"; then
      warn "Ollama model pull failed: $model"
      failed_models+=("$model")
    fi
  done

  if ((${#failed_models[@]})); then
    warn "Failed Ollama model pulls: ${failed_models[*]}"
    warn "The installer will continue. Retry failed pulls manually or rerun the ollama task later."
  fi
}

normalize_seconds() {
  local value="$1"
  local fallback="$2"

  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
  else
    warn "Invalid seconds value '$value'; using $fallback."
    printf '%s' "$fallback"
  fi
}

wait_for_ollama_server() {
  if (( DRY_RUN )); then
    return 0
  fi

  if ollama list >/dev/null 2>&1; then
    return 0
  fi

  local delay wait_seconds deadline
  delay="$(normalize_seconds "$OLLAMA_STARTUP_DELAY_SECONDS" 3)"
  wait_seconds="$(normalize_seconds "$OLLAMA_STARTUP_WAIT_SECONDS" 20)"

  if (( delay > 0 )); then
    log "Waiting ${delay}s for Ollama service startup."
    sleep "$delay"
  fi

  if ollama list >/dev/null 2>&1; then
    return 0
  fi

  if has_command systemctl && systemctl list-unit-files ollama.service >/dev/null 2>&1; then
    run_optional sudo systemctl start ollama.service
  fi

  deadline=$((SECONDS + wait_seconds))
  while (( SECONDS < deadline )); do
    if ollama list >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
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

install_opencode() {
  if has_command opencode; then
    log "opencode is already installed at $(command -v opencode)."
    return
  fi
  run_bash "curl -fsSL https://opencode.ai/install | bash"
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

install_gnome_disable_key_repeat() {
  if ! has_command gsettings; then
    warn "gsettings was not found. Disable repeat keys manually in Ubuntu Settings > Accessibility > Typing."
    return
  fi

  if [[ "$(gsettings writable org.gnome.desktop.peripherals.keyboard repeat 2>/dev/null || true)" != "true" ]]; then
    warn "GNOME keyboard repeat setting is not writable in this session."
    return
  fi

  run gsettings set org.gnome.desktop.peripherals.keyboard repeat false
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

current_user_has_group() {
  id -nG 2>/dev/null | tr ' ' '\n' | grep -qx "$1"
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

install_docker_desktop_prereqs() {
  apt_install \
    cpu-checker \
    dbus-user-session \
    gnome-terminal \
    pass \
    qemu-system-x86 \
    qemu-utils \
    uidmap

  run sudo groupadd -f kvm
  run sudo usermod -aG kvm "$USER"

  run_optional sudo modprobe kvm

  local cpu_vendor
  cpu_vendor="$(lscpu 2>/dev/null | awk -F: '/Vendor ID/{gsub(/^[ \t]+/, "", $2); print $2; exit}' || true)"
  case "$cpu_vendor" in
    GenuineIntel)
      run_optional sudo modprobe kvm_intel
      ;;
    AuthenticAMD)
      run_optional sudo modprobe kvm_amd
      ;;
    "")
      warn "Could not detect CPU vendor for KVM module loading."
      ;;
    *)
      warn "Unknown CPU vendor '$cpu_vendor'; loaded generic kvm module only."
      ;;
  esac

  if [[ -e /dev/kvm ]]; then
    run ls -al /dev/kvm
  else
    warn "/dev/kvm was not found. Docker Desktop may not start until virtualization or nested virtualization is enabled."
  fi

  if has_command kvm-ok; then
    run_optional kvm-ok
  fi

  if ! current_user_has_group kvm; then
    warn "Your current login session is not in the kvm group yet. Log out and back in before starting Docker Desktop."
  fi
}

install_docker_desktop_pass() {
  apt_install pass gnupg

  if [[ -f "$HOME/.password-store/.gpg-id" ]]; then
    log "pass is already initialized at $HOME/.password-store."
    return
  fi

  if [[ -n "${DOCKER_PASS_GPG_ID:-}" ]]; then
    run pass init "$DOCKER_PASS_GPG_ID"
    return
  fi

  warn "pass is installed but not initialized. Docker Desktop sign-in needs pass."
  cat <<'EOF'

To initialize pass for Docker Desktop:
  gpg --generate-key
  gpg --list-secret-keys --keyid-format=long
  pass init <your-gpg-key-id>

Or rerun this task with:
  DOCKER_PASS_GPG_ID=<your-gpg-key-id> ./install.sh --only docker_desktop_pass
EOF
}

start_docker_desktop_service() {
  if ! systemctl --user list-unit-files docker-desktop.service >/dev/null 2>&1; then
    warn "docker-desktop.service was not found. Docker Desktop may not be installed yet."
    return
  fi

  run_optional systemctl --user daemon-reload
  run_optional systemctl --user enable docker-desktop.service

  if ! current_user_has_group kvm; then
    warn "Skipping Docker Desktop start in this session because kvm group membership is not active yet."
    warn "After logging out and back in, try: systemctl --user start docker-desktop"
    return
  fi

  run_optional systemctl --user start docker-desktop.service
  warn "If Docker Desktop still does not appear, run: ./scripts/docker-desktop-debug.sh"
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
  install_docker_desktop_prereqs

  deb="$(mktemp --suffix=.deb)"
  run curl -fsSLo "$deb" https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb
  run sudo apt-get install -y "$deb"
  rm -f "$deb"

  start_docker_desktop_service
}

setup_nvidia_container_toolkit_repo() {
  local tmpdir
  tmpdir="$(mktemp -d)"

  run curl -fsSLo "$tmpdir/nvidia-container-toolkit.gpgkey" https://nvidia.github.io/libnvidia-container/gpgkey
  run gpg --dearmor -o "$tmpdir/nvidia-container-toolkit-keyring.gpg" "$tmpdir/nvidia-container-toolkit.gpgkey"
  run sudo install -D -m 0644 "$tmpdir/nvidia-container-toolkit-keyring.gpg" /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

  run curl -fsSLo "$tmpdir/nvidia-container-toolkit.list" https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    "$tmpdir/nvidia-container-toolkit.list" > "$tmpdir/nvidia-container-toolkit.signed.list"
  run sudo install -D -m 0644 "$tmpdir/nvidia-container-toolkit.signed.list" /etc/apt/sources.list.d/nvidia-container-toolkit.list
  rm -rf "$tmpdir"

  run sudo apt-get update
  APT_UPDATED=1
}

install_nvidia_container_toolkit() {
  setup_nvidia_container_toolkit_repo
  run sudo apt-get install -y nvidia-container-toolkit

  if has_command nvidia-ctk; then
    run sudo nvidia-ctk runtime configure --runtime=docker
    run_optional sudo systemctl restart docker
  else
    warn "nvidia-ctk was not found after installing nvidia-container-toolkit."
  fi

  if ! has_command nvidia-smi; then
    warn "nvidia-smi was not found. The toolkit is installed, but GPU containers still need a working NVIDIA driver."
  fi
}

docker_exec_quiet() {
  if docker info >/dev/null 2>&1; then
    docker "$@" >/dev/null 2>&1
  elif sudo docker info >/dev/null 2>&1; then
    sudo docker "$@" >/dev/null 2>&1
  else
    return 1
  fi
}

docker_exec() {
  if docker info >/dev/null 2>&1; then
    run docker "$@"
  elif sudo docker info >/dev/null 2>&1; then
    run sudo docker "$@"
  else
    warn "Docker is installed but not reachable. Log out/in for docker group changes, start Docker Desktop, or start Docker Engine."
    return 1
  fi
}

install_open_webui() {
  if ! has_command docker; then
    warn "docker command was not found. Select Docker Engine or Docker Desktop first, then rerun open_webui."
    return
  fi

  if ! docker_exec_quiet info; then
    warn "Docker is not reachable yet. If Docker was just installed, log out/in or start Docker Desktop, then rerun open_webui."
    return
  fi

  local image
  image="$OPEN_WEBUI_IMAGE"

  local -a run_args=(
    -d
    -p "$OPEN_WEBUI_PORT:8080"
    --add-host=host.docker.internal:host-gateway
    -v open-webui:/app/backend/data
    --name "$OPEN_WEBUI_CONTAINER"
    --restart always
  )

  if [[ "${OPEN_WEBUI_GPU:-0}" == "1" ]]; then
    image="$OPEN_WEBUI_GPU_IMAGE"
    run_args+=(--gpus all)
  fi

  if docker_exec_quiet container inspect "$OPEN_WEBUI_CONTAINER"; then
    log "Open WebUI container '$OPEN_WEBUI_CONTAINER' already exists."
    docker_exec start "$OPEN_WEBUI_CONTAINER"
    warn "Open WebUI should be available at http://localhost:$OPEN_WEBUI_PORT if the container started cleanly."
    return
  fi

  docker_exec pull "$image"
  run_args+=("$image")
  docker_exec run "${run_args[@]}"
  warn "Open WebUI should be available at http://localhost:$OPEN_WEBUI_PORT."
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
    uv) install_uv ;;
    conda_miniconda) install_conda_miniconda ;;
    kanata) install_kanata ;;
    ollama) install_ollama ;;
    codex) install_codex ;;
    opencode) install_opencode ;;
    claude_code) install_claude_code ;;
    flatpak) install_flatpak ;;
    extension_manager) install_extension_manager ;;
    copyous) install_copyous ;;
    gnome_disable_key_repeat) install_gnome_disable_key_repeat ;;
    google_chrome) install_google_chrome ;;
    vscode) install_vscode ;;
    pandoc) install_pandoc ;;
    gh) install_gh ;;
    docker_engine) install_docker_engine ;;
    nvidia_container_toolkit) install_nvidia_container_toolkit ;;
    docker_desktop) install_docker_desktop ;;
    docker_desktop_pass) install_docker_desktop_pass ;;
    open_webui) install_open_webui ;;
    telegram) install_telegram ;;
    *) die "Unknown task id: $task" ;;
  esac
}

run_selected_tasks() {
  local task
  local status

  FAILED_TASKS=()
  FAILED_TASK_STATUSES=()

  for task in "${TASK_ORDER[@]}"; do
    if is_selected "$task"; then
      log "Starting task: $task"
      set +e
      (
        set -Eeuo pipefail
        run_task "$task"
      )
      status=$?
      set -Eeuo pipefail

      if (( status == 130 || status == 143 )); then
        die "Interrupted during task: $task"
      fi

      if (( status == 0 )); then
        log "Finished task: $task"
      else
        FAILED_TASKS+=("$task")
        FAILED_TASK_STATUSES+=("$status")
        warn "Task failed with exit status $status: $task. Continuing with remaining selected tasks."
      fi
    fi
  done
}

report_failed_tasks() {
  local i
  local failed_csv

  if ((${#FAILED_TASKS[@]} == 0)); then
    log "All selected tasks completed."
    return 0
  fi

  warn "Installer completed with failed tasks:"
  for i in "${!FAILED_TASKS[@]}"; do
    warn "- ${FAILED_TASKS[$i]} (exit status ${FAILED_TASK_STATUSES[$i]})"
  done
  failed_csv="$(IFS=,; printf '%s' "${FAILED_TASKS[*]}")"
  warn "Review the log at $LOG_FILE, then rerun failed tasks with: ./install.sh --only $failed_csv --yes"
  return 1
}

post_install_notes() {
  cat <<'EOF'

Post-install notes:
- Log out and back in for Kanata uinput/input group membership.
- Log out and back in for Docker, kvm, uinput, and input group membership.
- Reboot or log out/in if GNOME Software does not show Flathub apps yet.
- Open a new terminal for conda initialization to take effect.
- If Docker Desktop does not appear, try: systemctl --user start docker-desktop
- For Docker Desktop logs, run: ./scripts/docker-desktop-debug.sh
- Open WebUI runs at http://localhost:3000 by default after its container starts.
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
  report_failed_tasks
}

main "$@"
