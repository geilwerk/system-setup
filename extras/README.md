# Extras Installer

Optional service-oriented setup that is intentionally separate from the base desktop installer.

Run as your normal desktop user:

```bash
./extras/install-extras.sh
```

Default extras:

- `open_webui_stable`: installs Open WebUI with `uv tool install` and runs it on `http://localhost:3004`.
- `open_webui_latest`: runs `uvx --python 3.11 open-webui@latest` on `http://localhost:3005`.

Opt-in extras:

- `mcpo`: installs a user service for the Open WebUI MCP-to-OpenAPI bridge. It creates `~/.config/mcpo/mcpo.env` and only enables the service after `MCPO_API_KEY` is set.
- `open_terminal`: installs a system service for Open Terminal. It creates `/etc/default/open-terminal` and only enables the service after `OPEN_TERMINAL_API_KEY` is set.

Useful commands:

```bash
./extras/install-extras.sh --list
./extras/install-extras.sh --dry-run --no-tui
./extras/install-extras.sh --only mcpo,open_terminal
OPEN_TERMINAL_API_KEY="change-me" ./extras/install-extras.sh --only open_terminal
MCPO_API_KEY="change-me" ./extras/install-extras.sh --only mcpo
```

Notes:

- The base installer still provides the Docker Open WebUI container path. This extras installer is for native/systemd experiments.
- The stable Open WebUI service does not auto-update on restart. Rerun the extras installer or use `uv tool upgrade open-webui` when you intentionally want to move it.
- The latest Open WebUI service resolves `open-webui@latest` through `uvx` when the service starts, so keep its data directory separate from the stable service.
