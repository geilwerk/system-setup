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
- Conda is installed through the official Miniconda Linux installer at `~/miniconda3` by default. Override with `MINICONDA_PREFIX=/path/to/miniconda3`.
- Kanata group changes require logging out and back in before the user service can fully work.
- Flatpak/Flathub and GNOME Shell extension changes may also need a logout or reboot before GNOME Software and extensions notice everything.

## Layout

- [install.sh](install.sh): interactive installer.
- [docs/sources.md](docs/sources.md): source links and official commands used by this draft.
- [services/user](services/user): user systemd units copied by the installer.
- [services/system](services/system): placeholder for future system services.
- [udev](udev): placeholder for future udev rules.
- [config](config): placeholder for future packaged config files.
