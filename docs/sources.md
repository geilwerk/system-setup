# Install Sources

This file tracks the official source used for each installer command. The goal is to keep the shell script auditable and easy to revise after VM testing.

## Core

- `curl`, `ca-certificates`, `gnupg`, `git`, `build-essential`, `pandoc`, and other base packages use Ubuntu apt packages.
- No Snap packages are installed by this script.

Ubuntu 26.04 reference notes checked while revisiting service and Kanata behavior:

- <https://documentation.ubuntu.com/release-notes/26.04/>
- <https://documentation.ubuntu.com/release-notes/26.04/changes-since-previous-interim/>

The 26.04 notes did not surface a specific `uinput`/`input` group change, so the Kanata installer keeps the upstream `uinput` default and exposes a local override for VM/laptop testing.

## Rust

Source: <https://www.rust-lang.org/tools/install>

Command family:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

The installer runs the standard Rustup script with `-y` for unattended setup.

## Node via nvm

Sources:

- <https://nodejs.org/en/download>
- <https://github.com/nvm-sh/nvm>

Command family:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
nvm install --lts
```

The script defaults to `NVM_VERSION=0.40.3` and installs the latest LTS Node through nvm.

## uv

Source: <https://docs.astral.sh/uv/getting-started/installation/>

Command:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

The main installer uses Astral's standalone installer so `uv` and `uvx` are available for Python-based tools and the optional extras installer.

## Conda via Miniconda

Sources:

- <https://www.anaconda.com/docs/getting-started/miniconda/install/linux-install>
- <https://www.anaconda.com/docs/getting-started/advanced-install/silent-mode>

Command family:

```bash
curl -O https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash ./Miniconda3-latest-Linux-x86_64.sh -b -p "$HOME/miniconda3"
source "$HOME/miniconda3/bin/activate"
conda init --all
conda config --set auto_activate_base false
```

The installer uses Miniconda rather than the full Anaconda Distribution so this remains a lightweight `conda` install. On ARM64 Linux it uses the official `Linux-aarch64` installer filename.

## Kanata

Sources:

- <https://github.com/jtroo/kanata>
- In-repo config: `kanata-setup/kanata.kbd`

Command family:

```bash
cargo install kanata
install -D -m 0644 kanata-setup/kanata.kbd "$HOME/.config/kanata/kanata.kbd"
```

The installer also sets up the Linux `uinput` permissions and a user systemd service. Kanata's current Linux setup docs use the `uinput` group in the udev rule, so the installer keeps that default while allowing `KANATA_UINPUT_GROUP=input` for Ubuntu 26.04 testing if the local device permissions need it.

## Ollama

Source: <https://ollama.com/download/linux>

Command:

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

Configured model pulls:

```bash
ollama pull glm-5.1:cloud
ollama pull kimi-k2.6:cloud
ollama pull gemini-3-flash-preview:cloud
ollama pull minimax-m2.7:cloud
ollama pull mistral-large-3:675b-cloud
ollama pull gemma4:31b-cloud
ollama pull qwen3.5:397b-cloud
```

Override the default model list with `OLLAMA_MODELS="model-a model-b"`, or set `OLLAMA_MODELS=""` to skip model pulls.

The installer waits briefly for the Ollama system service before pulling models. Model pull failures are logged as warnings so the rest of the desktop install can continue.

## OpenAI Codex CLI

Source: <https://developers.openai.com/codex/cli/>

Command:

```bash
npm install -g @openai/codex
```

## Claude Code

Source: <https://docs.anthropic.com/en/docs/claude-code/setup>

Command:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

The script uses the native installer instead of npm to avoid npm permission and Node version coupling.

## OpenCode

Source: <https://opencode.ai/docs/>

Command:

```bash
curl -fsSL https://opencode.ai/install | bash
```

The installer uses OpenCode's official install script. The docs also list npm, Bun, pnpm, Yarn, Homebrew, Arch, Windows, and Docker options.

## Flatpak and Flathub

Sources:

- <https://flatpak.org/setup/Ubuntu>
- <https://flathub.org/setup/Ubuntu>

Command family:

```bash
sudo apt install flatpak gnome-software-plugin-flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

The script also installs `gnome-software` because this setup targets Ubuntu GNOME desktop.

## GNOME Extension Manager

Source: <https://flathub.org/apps/com.mattjakeman.ExtensionManager>

Command:

```bash
flatpak install flathub com.mattjakeman.ExtensionManager
```

## Copyous GNOME Extension

Source: <https://extensions.gnome.org/extension/7381/copyous/>

UUID:

```text
copyous@boerdereinar.dev
```

The installer uses the official extensions.gnome.org metadata endpoint for the current GNOME Shell major version, downloads the extension zip, installs it with `gnome-extensions`, and attempts to enable it.

## GNOME Repeat Keys

Source: local GNOME settings schema, verified with:

```bash
gsettings list-keys org.gnome.desktop.peripherals.keyboard
```

Command:

```bash
gsettings set org.gnome.desktop.peripherals.keyboard repeat false
```

Kanata handles repeat behavior better than GNOME's system repeat for this keyboard setup, so the installer disables GNOME repeat keys when the setting is writable.

## Google Chrome

Source: <https://www.google.com/chrome/>

Command family:

```bash
curl -fsSLo google-chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install ./google-chrome.deb
```

Google's deb package installs the Chrome apt source for future updates.

## Visual Studio Code

Source: <https://code.visualstudio.com/docs/setup/linux>

Command family:

```bash
sudo install -D -m 644 microsoft.gpg /usr/share/keyrings/microsoft.gpg
sudo install -D -m 644 vscode.sources /etc/apt/sources.list.d/vscode.sources
sudo apt install code
```

The script uses Microsoft's signed apt repository flow.

## GitHub CLI

Source: <https://github.com/cli/cli/blob/trunk/docs/install_linux.md>

Command family:

```bash
sudo mkdir -p -m 755 /etc/apt/keyrings
wget -nv -O- https://cli.github.com/packages/githubcli-archive-keyring.gpg
sudo apt install gh
```

The script uses the signed apt repository flow from the GitHub CLI docs.

## Docker Engine

Source: <https://docs.docker.com/engine/install/ubuntu/>

Command family:

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

## Docker Desktop

Sources:

- <https://docs.docker.com/desktop/setup/install/linux/>
- <https://docs.docker.com/desktop/setup/install/linux/ubuntu/>
- <https://docs.docker.com/desktop/setup/sign-in/>

Command family:

```bash
sudo apt install cpu-checker dbus-user-session gnome-terminal pass qemu-system-x86 qemu-utils uidmap
sudo usermod -aG kvm "$USER"
curl -fsSLo docker-desktop-amd64.deb https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb
sudo apt install ./docker-desktop-amd64.deb
systemctl --user start docker-desktop
```

Docker Desktop official support currently lists Ubuntu 26.04 and 24.04. The installer warns and skips it on 25.10 by default.

Docker Desktop for Linux runs a VM and needs KVM access. The installer adds the user to `kvm`, installs QEMU/KVM helper packages, checks `/dev/kvm`, and installs `pass` for credential storage. It does not auto-generate a GPG key by default; if `DOCKER_PASS_GPG_ID` is set, it runs `pass init "$DOCKER_PASS_GPG_ID"`.

## NVIDIA Container Toolkit

Source: <https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html>

Command family:

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

The installer assumes NVIDIA drivers are already handled elsewhere, matching the broader setup assumption that hardware drivers are automatic.

## Open WebUI

Source: <https://docs.openwebui.com/getting-started/quick-start/>

Command family:

```bash
docker run -d -p 3000:8080 --add-host=host.docker.internal:host-gateway -v open-webui:/app/backend/data --name open-webui --restart always ghcr.io/open-webui/open-webui:main
```

For NVIDIA GPU support, set `OPEN_WEBUI_GPU=1`; the installer uses the `:cuda` image and adds `--gpus all`.

The optional extras installer also supports native Open WebUI services. The upstream quick start documents the uv path as:

```bash
DATA_DIR=~/.open-webui uvx --python 3.11 open-webui@latest serve
```

The extras installer uses that command family for `open-webui-latest.service`, and uses `uv tool install open-webui` for a separate `open-webui-stable.service` that does not auto-resolve `@latest` on every service start.

## mcpo

Sources:

- <https://docs.openwebui.com/features/extensibility/plugin/tools/openapi-servers/mcp/>
- <https://github.com/open-webui/mcpo>

Command family:

```bash
uvx mcpo --port 8000 --api-key "your-secret-key" -- your_mcp_server_command
```

The extras installer templates a user service and a small `mcpo-gateway` wrapper. By default it runs Docker Desktop's MCP gateway command behind mcpo:

```bash
uvx mcpo --host 0.0.0.0 --port 8000 --api-key "$MCPO_API_KEY" -- docker --context desktop-linux mcp gateway run
```

Set `MCPO_API_KEY` before installing, or edit `~/.config/mcpo/mcpo.env` after installation and enable the service manually.

## Open Terminal

Source: <https://docs.openwebui.com/features/open-terminal/setup/installation/>

Command family:

```bash
uvx open-terminal run --host 0.0.0.0 --port 8000 --api-key your-secret-key
```

The extras installer templates a system service using the bare-metal uvx command. It does not enable or start the service until `OPEN_TERMINAL_API_KEY` is configured.

## Telegram

Source: <https://flathub.org/apps/org.telegram.desktop>

Command:

```bash
flatpak install flathub org.telegram.desktop
```
