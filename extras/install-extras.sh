#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
LOG_STAMP="$(date +%Y%m%d-%H%M%S)"

OPEN_WEBUI_STABLE_DATA_DIR="${OPEN_WEBUI_STABLE_DATA_DIR:-$HOME/.open-webui-stable}"
OPEN_WEBUI_LATEST_DATA_DIR="${OPEN_WEBUI_LATEST_DATA_DIR:-$HOME/.open-webui-latest}"
OPEN_WEBUI_STABLE_PORT="${OPEN_WEBUI_STABLE_PORT:-3004}"
OPEN_WEBUI_LATEST_PORT="${OPEN_WEBUI_LATEST_PORT:-3005}"
OPEN_WEBUI_HOST="${OPEN_WEBUI_HOST:-0.0.0.0}"
OPEN_WEBUI_PYTHON="${OPEN_WEBUI_PYTHON:-3.11}"
OPEN_WEBUI_STABLE_VERSION="${OPEN_WEBUI_STABLE_VERSION:-}"

OPEN_TERMINAL_HOST="${OPEN_TERMINAL_HOST:-0.0.0.0}"
OPEN_TERMINAL_PORT="${OPEN_TERMINAL_PORT:-9900}"
OPEN_TERMINAL_API_KEY="${OPEN_TERMINAL_API_KEY:-}"

MCPO_HOST="${MCPO_HOST:-0.0.0.0}"
MCPO_PORT="${MCPO_PORT:-8000}"
MCPO_API_KEY="${MCPO_API_KEY:-}"
MCPO_BACKEND_COMMAND="${MCPO_BACKEND_COMMAND:-docker --context desktop-linux mcp gateway run}"

DRY_RUN=0
NO_TUI=0
ASSUME_YES=0
ONLY_TASKS=""

declare -A SELECTED=()

TASK_ORDER=(
  open_webui_stable
  open_webui_latest
  mcpo
  open_terminal
)

DEFAULT_TASKS=(
  open_webui_stable
  open_webui_latest
)

usage() {
  cat <<'EOF'
Usage: ./extras/install-extras.sh [options]

Options:
  --dry-run              Show selected extras without installing anything.
  --no-tui               Use the default extras without showing checkboxes.
  --only a,b,c           Run only the comma-separated extra ids.
  --yes                  Do not ask final confirmation questions.
  --list                 List available extra ids.
  -h, --help             Show this help.

Environment:
  OPEN_WEBUI_STABLE_DATA_DIR=$HOME/.open-webui-stable
  OPEN_WEBUI_LATEST_DATA_DIR=$HOME/.open-webui-latest
  OPEN_WEBUI_STABLE_PORT=3004
  OPEN_WEBUI_LATEST_PORT=3005
  OPEN_WEBUI_STABLE_VERSION=<optional exact package version>
  OPEN_TERMINAL_API_KEY=<required to enable/start open-terminal.service>
  MCPO_API_KEY=<required to enable/start mcpo.service>
  MCPO_BACKEND_COMMAND="docker --context desktop-linux mcp gateway run"
EOF
}

list_tasks() {
  cat <<'EOF'
open_webui_stable   Native Open WebUI service using uv tool install.
open_webui_latest   Native Open WebUI service using uvx open-webui@latest.
mcpo                User service for mcpo MCP-to-OpenAPI bridge.
open_terminal       System service for Open Terminal via uvx.
EOF
}

log() {
  printf '\n\033[1;34m==>\033[0m %s\n' "$*"
}

warn() {
  printf '\n\033[1;33mWARN:\033[0m %s\n' "$*" >&2
}

die() {
  printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2
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

select_with_tui() {
  if (( NO_TUI )) || [[ ! -t 0 ]] || [[ ! -t 1 ]] || ! command -v whiptail >/dev/null 2>&1; then
    select_defaults
    return
  fi

  SELECTED=()
  local output
  output="$(whiptail \
    --title "Ubuntu Setup: Extras" \
    --separate-output \
    --checklist "These make filesystem/service edits beyond the base desktop setup." \
    18 94 8 \
    "open_webui_stable" "Open WebUI service via uv tool install on port 3004" ON \
    "open_webui_latest" "Open WebUI service via uvx open-webui@latest on port 3005" ON \
    "mcpo" "mcpo user service; requires MCPO_API_KEY before it is started" OFF \
    "open_terminal" "Open Terminal system service; requires OPEN_TERMINAL_API_KEY" OFF \
    3>&1 1>&2 2>&3)" || die "Extras installer cancelled."

  local task
  while IFS= read -r task; do
    [[ -n "$task" ]] && select_task "$task"
  done <<< "$output"
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
    task_exists "$task" || die "Unknown extra id: $task. Use --list to see available extras."
  done
}

confirm_selection() {
  local selected
  selected="$(selected_tasks_string)"
  [[ -n "$selected" ]] || die "No extras selected."

  printf '\nSelected extras:\n%s\n' "$selected"

  if (( DRY_RUN )) || (( ASSUME_YES )); then
    return
  fi

  if command -v whiptail >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
    whiptail --title "Confirm Extras" --yesno "Install the selected extras now?" 10 72 || die "Extras installer cancelled."
  else
    read -r -p "Install the selected extras now? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || die "Extras installer cancelled."
  fi
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

source_local_bin() {
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
}

install_uv_if_needed() {
  source_local_bin
  if ! has_command uv || ! has_command uvx; then
    run_bash "curl -LsSf https://astral.sh/uv/install.sh | sh"
  fi

  if (( DRY_RUN )); then
    return
  fi

  source_local_bin
  has_command uv || die "uv was not found after installation."
  has_command uvx || die "uvx was not found after installation."
}

uv_tool_installed() {
  uv tool list | awk '{ print $1 }' | grep -Fxq "$1"
}

dependency_warnings() {
  local warnings=()

  source_local_bin

  if (is_selected open_webui_stable || is_selected open_webui_latest || is_selected mcpo || is_selected open_terminal) && ! has_command uvx; then
    warnings+=("Selected extras use uvx/uv. The extras installer will install uv if it is missing.")
  fi
  if is_selected mcpo && ! has_command docker; then
    warnings+=("mcpo defaults to Docker Desktop's MCP gateway command, but docker was not found.")
  fi
  if is_selected mcpo && [[ -z "$MCPO_API_KEY" ]] && [[ ! -s "$HOME/.config/mcpo/mcpo.env" ]]; then
    warnings+=("mcpo will be installed but not enabled until MCPO_API_KEY is set.")
  fi
  if is_selected open_terminal && [[ -z "$OPEN_TERMINAL_API_KEY" ]] && [[ ! -s /etc/default/open-terminal ]]; then
    warnings+=("Open Terminal will be installed but not enabled until OPEN_TERMINAL_API_KEY is set.")
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
    whiptail --title "Extras Warning" --yesno "$message\n\nContinue anyway?" 16 86 || die "Extras installer cancelled."
  else
    read -r -p "Continue anyway? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || die "Extras installer cancelled."
  fi
}

sed_escape() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

render_template() {
  local src="$1"
  local dest="$2"
  shift 2

  cp "$src" "$dest"
  while (($#)); do
    local key="$1"
    local value="$2"
    local escaped
    shift 2
    escaped="$(sed_escape "$value")"
    sed -i "s|$key|$escaped|g" "$dest"
  done
}

install_root_file() {
  local src="$1"
  local dest="$2"
  local mode="$3"

  if (( DRY_RUN )); then
    log "sudo install -D -m $mode $src $dest"
    return
  fi

  if sudo test -e "$dest" && ! sudo cmp -s "$src" "$dest"; then
    sudo cp -a "$dest" "$dest.bak-$LOG_STAMP"
  fi
  sudo install -D -m "$mode" "$src" "$dest"
}

install_root_file_if_missing() {
  local src="$1"
  local dest="$2"
  local mode="$3"

  if (( DRY_RUN )); then
    log "sudo install -D -m $mode $src $dest if missing"
    return
  fi

  if sudo test -e "$dest" 2>/dev/null; then
    log "$dest already exists; leaving it in place."
    return
  fi

  install_root_file "$src" "$dest" "$mode"
}

install_user_file() {
  local src="$1"
  local dest="$2"
  local mode="$3"

  if (( DRY_RUN )); then
    log "install -D -m $mode $src $dest"
    return
  fi

  if [[ -e "$dest" ]] && ! cmp -s "$src" "$dest"; then
    cp -a "$dest" "$dest.bak-$LOG_STAMP"
  fi
  install -D -m "$mode" "$src" "$dest"
}

install_user_file_if_missing() {
  local src="$1"
  local dest="$2"
  local mode="$3"

  if [[ -e "$dest" ]]; then
    log "$dest already exists; leaving it in place."
    return
  fi

  install_user_file "$src" "$dest" "$mode"
}

root_env_has_value() {
  local file="$1"
  local key="$2"

  sudo awk -F= -v key="$key" '
    $1 == key {
      value = $0
      sub("^[^=]*=", "", value)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      if (value != "") found = 1
    }
    END { exit found ? 0 : 1 }
  ' "$file" 2>/dev/null
}

user_env_has_value() {
  local file="$1"
  local key="$2"

  awk -F= -v key="$key" '
    $1 == key {
      value = $0
      sub("^[^=]*=", "", value)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      if (value != "") found = 1
    }
    END { exit found ? 0 : 1 }
  ' "$file" 2>/dev/null
}

install_open_webui_env() {
  local name="$1"
  local data_dir="$2"
  local port="$3"
  local dest="/etc/default/open-webui-$name"
  local tmp

  tmp="$(mktemp)"
  render_template "$SCRIPT_DIR/env/open-webui.env.in" "$tmp" \
    "@DATA_DIR@" "$data_dir" \
    "@HOST@" "$OPEN_WEBUI_HOST" \
    "@PORT@" "$port" \
    "@PYTHON@" "$OPEN_WEBUI_PYTHON" \
    "@WEBUI_URL@" "http://localhost:$port"
  install_root_file_if_missing "$tmp" "$dest" 0600
  rm -f "$tmp"
}

install_open_webui_service() {
  local template="$1"
  local service="$2"
  local tmp

  tmp="$(mktemp)"
  render_template "$template" "$tmp" \
    "@USER@" "$USER" \
    "@GROUP@" "$(id -gn)" \
    "@HOME@" "$HOME"
  install_root_file "$tmp" "/etc/systemd/system/$service" 0644
  rm -f "$tmp"

  run sudo systemctl daemon-reload
  run sudo systemctl enable --now "$service"
}

install_open_webui_stable() {
  install_uv_if_needed
  run mkdir -p "$OPEN_WEBUI_STABLE_DATA_DIR"

  local package
  package="open-webui"
  if [[ -n "$OPEN_WEBUI_STABLE_VERSION" ]]; then
    package="open-webui==$OPEN_WEBUI_STABLE_VERSION"
  fi

  if [[ -n "$OPEN_WEBUI_STABLE_VERSION" ]]; then
    run uv tool install --force --python "$OPEN_WEBUI_PYTHON" "$package"
  elif (( DRY_RUN )); then
    run uv tool install --python "$OPEN_WEBUI_PYTHON" "$package"
  elif uv_tool_installed open-webui; then
    log "open-webui is already installed as a uv tool."
  else
    run uv tool install --python "$OPEN_WEBUI_PYTHON" "$package"
  fi
  install_open_webui_env "stable" "$OPEN_WEBUI_STABLE_DATA_DIR" "$OPEN_WEBUI_STABLE_PORT"
  install_open_webui_service "$SCRIPT_DIR/services/system/open-webui-stable.service.in" "open-webui-stable.service"
}

install_open_webui_latest() {
  install_uv_if_needed
  run mkdir -p "$OPEN_WEBUI_LATEST_DATA_DIR"
  install_open_webui_env "latest" "$OPEN_WEBUI_LATEST_DATA_DIR" "$OPEN_WEBUI_LATEST_PORT"
  install_open_webui_service "$SCRIPT_DIR/services/system/open-webui-latest.service.in" "open-webui-latest.service"
}

install_open_terminal() {
  install_uv_if_needed

  local env_tmp
  env_tmp="$(mktemp)"
  render_template "$SCRIPT_DIR/env/open-terminal.env.in" "$env_tmp" \
    "@HOST@" "$OPEN_TERMINAL_HOST" \
    "@PORT@" "$OPEN_TERMINAL_PORT" \
    "@API_KEY@" "$OPEN_TERMINAL_API_KEY"

  if (( ! DRY_RUN )) && [[ -n "$OPEN_TERMINAL_API_KEY" ]] && sudo test -e /etc/default/open-terminal && ! root_env_has_value /etc/default/open-terminal OPEN_TERMINAL_API_KEY; then
    install_root_file "$env_tmp" /etc/default/open-terminal 0600
  else
    install_root_file_if_missing "$env_tmp" /etc/default/open-terminal 0600
  fi
  rm -f "$env_tmp"

  local service_tmp
  service_tmp="$(mktemp)"
  render_template "$SCRIPT_DIR/services/system/open-terminal.service.in" "$service_tmp" \
    "@USER@" "$USER" \
    "@GROUP@" "$(id -gn)" \
    "@HOME@" "$HOME"
  install_root_file "$service_tmp" /etc/systemd/system/open-terminal.service 0644
  rm -f "$service_tmp"

  run sudo systemctl daemon-reload
  if (( DRY_RUN )); then
    log "Would enable open-terminal.service if OPEN_TERMINAL_API_KEY is configured."
    return
  fi

  if root_env_has_value /etc/default/open-terminal OPEN_TERMINAL_API_KEY; then
    run sudo systemctl enable --now open-terminal.service
  else
    warn "Open Terminal service installed but not enabled. Add OPEN_TERMINAL_API_KEY to /etc/default/open-terminal, then run: sudo systemctl enable --now open-terminal.service"
  fi
}

install_mcpo() {
  install_uv_if_needed

  local env_tmp env_dest
  env_dest="$HOME/.config/mcpo/mcpo.env"
  env_tmp="$(mktemp)"
  render_template "$SCRIPT_DIR/env/mcpo.env.in" "$env_tmp" \
    "@HOST@" "$MCPO_HOST" \
    "@PORT@" "$MCPO_PORT" \
    "@API_KEY@" "$MCPO_API_KEY" \
    "@BACKEND_COMMAND@" "$MCPO_BACKEND_COMMAND"

  if [[ -n "$MCPO_API_KEY" && -e "$env_dest" ]] && ! user_env_has_value "$env_dest" MCPO_API_KEY; then
    install_user_file "$env_tmp" "$env_dest" 0600
  else
    install_user_file_if_missing "$env_tmp" "$env_dest" 0600
  fi
  rm -f "$env_tmp"

  install_user_file "$SCRIPT_DIR/bin/mcpo-gateway" "$HOME/.local/bin/mcpo-gateway" 0755
  install_user_file "$SCRIPT_DIR/services/user/mcpo.service.in" "$HOME/.config/systemd/user/mcpo.service" 0644

  run_optional systemctl --user daemon-reload
  if (( DRY_RUN )); then
    log "Would enable mcpo.service if MCPO_API_KEY is configured."
    return
  fi

  if user_env_has_value "$env_dest" MCPO_API_KEY; then
    run_optional systemctl --user enable --now mcpo.service
  else
    warn "mcpo service installed but not enabled. Add MCPO_API_KEY to $env_dest, then run: systemctl --user enable --now mcpo.service"
  fi
}

run_task() {
  case "$1" in
    open_webui_stable) install_open_webui_stable ;;
    open_webui_latest) install_open_webui_latest ;;
    mcpo) install_mcpo ;;
    open_terminal) install_open_terminal ;;
    *) die "Unknown extra id: $1" ;;
  esac
}

main() {
  require_regular_user
  parse_args "$@"

  if [[ -n "$ONLY_TASKS" ]]; then
    select_only_tasks
  else
    select_with_tui
  fi

  validate_selected_tasks
  dependency_warnings
  confirm_selection

  local task
  for task in "${TASK_ORDER[@]}"; do
    if is_selected "$task"; then
      run_task "$task"
    fi
  done

  log "Extras complete."
}

main "$@"
