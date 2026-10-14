# Zomboid Range Select

Prototype v0.1.0 (Project Zomboid Build 42), developed independently from the workshop mod Controller Multi-Select. No upstream code is included.

## Gamepad

- **Tap A**: vanilla context menu (if no selection), or context menu for selected items.
- **Hold A + D-pad up/down**: select a contiguous range. D-pad reversing direction shrinks the in-progress range.
- **Release A**: commit the range. Previously selected ranges remain.
- **Hold A + D-pad again**: add another non-contiguous range.
- **X**: transfer selected items using normal PZ inventory transfer actions.
- **B**: clear a stored selection (otherwise normal vanilla action).

The mod is strictly local UI input logic; no server-side scripts or permissions are added.

## Install on macOS (without publishing to Workshop)

With the extracted repository in the current directory:

```sh
mkdir -p "$HOME/Zomboid/mods"
ditto Contents/mods/ZomboidRangeSelect "$HOME/Zomboid/mods/ZomboidRangeSelect"
```

Then start PZ, enable **Zomboid Range Select** under Mods and enable it for your save. Disable **Controller Multi-Select** at the same time to prevent overlapping input hooks. Restart PZ after changing controller mods.

## Testing

```sh
lua tests/test_core.lua
find Contents -name '*.lua' -exec luac -p {} \;
```

The tests exercise **only the portable selection state**, not PZ's runtime/controller integration. In-game verification is needed before publishing.

## Known risks / validation required

1. A is deferred until release. Check interaction timing with the exact game build and controller layout.
2. Input handling currently depends on `Joypad.AButton` and `JoypadButton.A:isDown`, and on `ISInventoryPage` / `ISInventoryPane` hooks. Confirm against installed B42 files.
3. Stacked/collapsed inventory rows, switching bags, sorting while selecting and scrolling need in-game checks.
4. Verify transfer safety for favorites, equipped/heavy items, multi-player clients and mixed item stacks; vanilla context-menu transfer helpers are used.
5. Inventory-screen UI in icon mode is intentionally unsupported.
6. Other inventory/controller mods may override the same methods depending on load order.

## Publishing

Source is ready for a GitHub repository. `.github/workflows/ci.yml` checks syntax, runs Lua state tests and uploads the Workshop-shaped ZIP. To publish on Steam Workshop, set the appropriate Workshop ID in `workshop.txt` after the initial upload using the game's Workshop UI.

**License:** not yet selected; don't republish source as an open-source licensed mod until a license is added deliberately.
