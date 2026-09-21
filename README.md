# Omarchy Window Switcher

A Windows-style MRU Alt-Tab switcher with a passive, theme-aware Omarchy
overlay.

The switcher freezes the current window history when Alt-Tab starts, previews
each selection immediately, and promotes only the final selection when Alt is
released. Alt-Shift-Tab cycles in reverse.

## Requirements

- Omarchy with the Quickshell overlay plugin system
- Hyprland with Lua configuration support

## Install

Install and enable the Omarchy plugin:

```bash
omarchy plugin add https://github.com/NicolasDorier/omarchy-window-switcher.git --enable
```

Load the switching behavior from your Hyprland Lua configuration:

```lua
local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
dofile(config_home .. "/omarchy/plugins/nicolasdorier.window-switcher/hypr/window-switcher.lua")
```

Reload Hyprland after adding the loader:

```bash
hyprctl reload
hyprctl configerrors
```

## Uninstall

Remove the Lua loader from your Hyprland configuration, then remove the plugin:

```bash
omarchy plugin remove nicolasdorier.window-switcher
```

## Validation

```bash
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell WindowSwitcher.qml
luac -p hypr/window-switcher.lua
```

See [docs/architecture.md](docs/architecture.md) for the integration design,
runtime state format, reload behavior, and troubleshooting.

## License

MIT
