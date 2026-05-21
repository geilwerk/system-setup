# Ubuntu System Setup

Interactive setup script for a fresh Ubuntu desktop install.

The first target is Ubuntu 25.10/26.04 on a VM, with a bias toward official vendor install commands and no Snap packages unless there is no practical alternative.

## Quick Start

Run as your normal desktop user, not with `sudo`:

```bash
./install.sh
```

The script bootstraps the minimum tools it needs for the TUI (`curl`, `ca-certificates`, and `whiptail`), then shows checkbox groups for:

- Core system dependencies
- Development runtimes and CLIs
- Conda through Miniconda
- Desktop applications
- GNOME extensions
- Container tooling
- Local AI/container helpers
- Keyboard setup

Dependency-like items such as Node and Rust can be unchecked, but the installer will warn if a selected app expects them.

## Useful Flags

```bash
./install.sh --dry-run
./install.sh --no-tui
./install.sh --only base,rust,node_nvm,kanata
./install.sh --list
```

## Current Notes

- Docker Desktop official docs currently list Ubuntu 26.04 and 24.04 support, not Ubuntu 25.10. The installer skips Docker Desktop on 25.10 unless `ALLOW_UNSUPPORTED_DOCKER_DESKTOP=1` is set.
- Docker Desktop setup now installs KVM/QEMU prerequisites, adds the user to `kvm`, installs `pass`, and can initialize `pass` when `DOCKER_PASS_GPG_ID` is provided.
- If Docker Desktop still silently fails from the app launcher, run `./scripts/docker-desktop-debug.sh` for service logs and KVM checks.
- Docker Engine and Docker Desktop can coexist, but Docker recommends stopping Engine while using Desktop if ports or resources get weird: `sudo systemctl stop docker docker.socket containerd`.
- Open WebUI is installed as a Docker container at `http://localhost:3000` by default. Set `OPEN_WEBUI_GPU=1` to use the CUDA image.
- Ollama pulls the configured cloud model list after install. Override with `OLLAMA_MODELS="model-a model-b"` or set `OLLAMA_MODELS=""` to skip pulls.
- Conda is installed through the official Miniconda Linux installer at `~/miniconda3` by default. Override with `MINICONDA_PREFIX=/path/to/miniconda3`.
- Kanata group changes require logging out and back in before the user service can fully work.
- Flatpak/Flathub and GNOME Shell extension changes may also need a logout or reboot before GNOME Software and extensions notice everything.

## Layout

- [install.sh](install.sh): interactive installer.
- [kanata-setup](kanata-setup): Kanata config and legacy setup notes used by the installer.
- [todos.md](todos.md): casual backlog for things to add or revisit.
- [docs/sources.md](docs/sources.md): source links and official commands used by this draft.
- [scripts](scripts): troubleshooting and helper scripts.
- [services/user](services/user): user systemd units copied by the installer.
- [services/system](services/system): placeholder for future system services.
- [udev](udev): placeholder for future udev rules.
- [config](config): placeholder for future packaged config files.
