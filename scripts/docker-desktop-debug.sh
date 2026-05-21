#!/usr/bin/env bash
set -uo pipefail

section() {
  printf '\n== %s ==\n' "$1"
}

run() {
  printf '$ %s\n' "$*"
  "$@"
}

section "User And Groups"
run id

section "KVM Device"
if [[ -e /dev/kvm ]]; then
  run ls -al /dev/kvm
else
  printf '/dev/kvm is missing. Docker Desktop needs KVM virtualization support.\n'
fi

section "KVM Modules"
run lsmod | grep kvm || true

section "kvm-ok"
if command -v kvm-ok >/dev/null 2>&1; then
  run kvm-ok || true
else
  printf 'kvm-ok is not installed. Install cpu-checker to use it.\n'
fi

section "Docker Desktop User Service"
run systemctl --user status docker-desktop --no-pager || true

section "Docker Desktop Journal"
run journalctl --user -u docker-desktop -n 200 --no-pager || true

section "Docker CLI"
if command -v docker >/dev/null 2>&1; then
  run docker --version || true
  run docker context ls || true
  run docker info || true
else
  printf 'docker command is not installed.\n'
fi

section "Desktop File"
if [[ -f /usr/share/applications/docker-desktop.desktop ]]; then
  run sed -n '1,160p' /usr/share/applications/docker-desktop.desktop
else
  printf 'Docker Desktop desktop file was not found.\n'
fi

