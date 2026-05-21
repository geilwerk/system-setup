# Setup Todos

Casual parking lot for things to add, fix, or sanity-check while this installer evolves.

## Add Next

- [x] Add Open WebUI.
- [x] Add opencode.
- [x] Add NVIDIA Container Toolkit.
- [x] Add Docker Desktop setup step to put the user in the `kvm` group.
- [x] Add Docker Desktop `pass` setup helper.
- [ ] Decide whether we ever want fully automated Docker Desktop GPG key generation, or whether explicit `DOCKER_PASS_GPG_ID` is the right permanent boundary.

## Settings To Automate

- [x] Disable Ubuntu/GNOME repeat keys if possible, because system repeat interferes with Kanata repeat behavior.
- [ ] Add more GNOME settings once they come up during VM testing.

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
