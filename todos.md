# Setup Todos

Casual parking lot for things to add, fix, or sanity-check while this installer evolves.

## Add Next

- [x] Add Open WebUI.
- [x] Add uv/uvx.
- [x] Add a separate extras installer for native Open WebUI service experiments.
- [x] Add optional mcpo and Open Terminal service templates without committing local secrets.
- [x] Add opencode.
- [x] Add NVIDIA Container Toolkit.
- [x] Add Docker Desktop setup step to put the user in the `kvm` group.
- [x] Add Docker Desktop `pass` setup helper.
- [ ] Decide whether we ever want fully automated Docker Desktop GPG key generation, or whether explicit `DOCKER_PASS_GPG_ID` is the right permanent boundary.

## Settings To Automate

- [x] Disable Ubuntu/GNOME repeat keys if possible, because system repeat interferes with Kanata repeat behavior.
- [ ] Add more GNOME settings once they come up during VM testing.

## Kanata Follow-Ups

- [ ] Test Kanata on Ubuntu 26.04+ with the default `KANATA_UINPUT_GROUP=uinput`.
- [ ] If 26.04 needs the laptop workaround, rerun Kanata setup with `KANATA_UINPUT_GROUP=input` and make that the documented path.

## Extras Follow-Ups

- [ ] Decide whether native Open WebUI should stay as two services, or whether Docker should remain the only everyday Open WebUI path.
- [ ] Decide whether `mcpo` and Open Terminal are still useful now that Open WebUI has native MCP support.
- [ ] Add uninstall/disable helpers for extras services once the VM shape settles.

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
