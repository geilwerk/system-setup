# Setup Todos

Casual parking lot for things to add, fix, or sanity-check while this installer evolves.

## Add Next

- [ ] Add Open WebUI.
- [ ] Add opencode.
- [ ] Add NVIDIA Container Toolkit.
- [ ] Add Docker Desktop setup step to put the user in the `kvm` group.
- [ ] Investigate whether Docker Desktop setup should initialize `pass` with a new GPG key.

## Settings To Automate

- [ ] Disable Ubuntu/GNOME repeat keys if possible, because system repeat interferes with Kanata repeat behavior.

## Kanata Follow-Ups

- [ ] Test Kanata on Ubuntu 26.04+ and document/fix the `input`/`uinput` group issue if it still exists.

## Installer Utility Ideas

- [ ] Add an uninstall mode that reverses anything the installer does where practical.
- [ ] Add a reinstall mode for selected tasks.
- [ ] Keep tightening idempotency so rerunning the script is boring in the best possible way.

## Update Helper Idea

- [ ] Consider splitting non-package-manager updates into a separate helper utility.
- [ ] Track update commands for tools like Ollama that update by rerunning the installer command.
- [ ] Check CLI `--help` output for native `update` or `upgrade` commands before using a generic update-all path.
- [ ] Exclude tools from update-all when their update command is risky, interactive, or unclear.

## Working Rule

- [ ] When adding a new installer item, also add its official source and command notes to `docs/sources.md`.

