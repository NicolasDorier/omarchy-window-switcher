# Architecture

## Components

`hypr/window-switcher.lua` returns a module whose `setup` function owns the
Alt-Tab bindings, MRU history, selection, and focus changes.
`WindowSwitcher.qml` is a passive Omarchy overlay that only renders state; it
does not capture keyboard or pointer input.

When an Alt-Tab session starts, the Lua code freezes the current history with
the active window first. Regular Alt-Tab selects the second entry, while
Alt-Shift-Tab starts from the end. Releasing Alt promotes only the final
selection while preserving the relative order of every other window.

One `session` table contains the frozen history, selection, direction, origin,
and monitor. A `nil` session means Alt-Tab is inactive.

The switcher has no knowledge of floating-terminal tags or parking workspaces.
Callers can inject an asynchronous `prepare_focus(window, callback)` function
through `setup`. The callback must receive a truthy first argument when the
window is ready to focus. Without an adapter, preparation completes immediately.

The dotfiles integration injects `floating_terminal.prepare_focus`. That module
restores parked terminals and hides a workspace's visible terminal before a
different window there is focused. Keeping those rules in their owning module
prevents the switcher and terminal state machines from diverging.

## Runtime State

The Lua code writes the current selection to:

```text
$XDG_RUNTIME_DIR/omarchy-window-switcher.json
```

The version 1 document contains the overlay visibility, origin monitor,
selected zero-based index, and visible windows:

```json
{
  "version": 1,
  "open": true,
  "monitor": "eDP-1",
  "selected": 1,
  "windows": [
    {
      "title": "Terminal",
      "className": "com.mitchellh.ghostty"
    }
  ]
}
```

Outside an Alt-Tab session, the file contains:

```json
{"version":1,"open":false}
```

The QML `FileView` watches this file and updates the overlay on each write. An
invalid or partial document closes the overlay instead of leaving stale state
visible. The overlay is click-through, appears only on the origin monitor, and
uses Omarchy's current menu colors, spacing, typography, and borders.

## Window Icons

Icons are resolved from matching desktop entries before falling back to the
window class. Brave tabs whose titles identify Gmail or GitHub use the bundled
site icons.

## Reloading

Hyprland automatically reloads Lua configuration changes. Validate a reload
with:

```bash
hyprctl reload
hyprctl configerrors
```

Omarchy detects local plugin changes, but loaded QML can remain cached. Restart
the shell after changing `WindowSwitcher.qml`:

```bash
omarchy restart shell
```

A rescan is sufficient when only plugin discovery changed:

```bash
omarchy-shell shell rescanPlugins
```

If the overlay does not appear, verify that the runtime state becomes
`"open":true` while Alt is held and that Omarchy reports the plugin as enabled:

```bash
omarchy plugin list --json | jq \
  '.[] | select(.id == "nicolasdorier.window-switcher")'
```
