# Zomboid Range Select

Prototype v0.1.2 (Project Zomboid Build 42), developed independently from the workshop mod Controller Multi-Select. No upstream code is included.

## Gamepad

- **A**: normal context menu, or a context menu for your current multi-selection.
- **Hold RT + D-pad up/down**: select a contiguous range. D-pad reversing direction shrinks the in-progress range.
- **Release RT**: commit the range. Previously selected ranges remain.
- **Hold RT + D-pad again**: add another non-contiguous range.
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


## Troubleshooting gamepad input

If the mod loads but RT+D-pad does nothing, first make sure PZ is actually controlling your **character** with the gamepad (not only moving a Steam Input mouse pointer). In the in-game controller options verify the device, use the game's controller takeover/assignment, and navigate the inventory using the controller's D-pad.

On macOS, after a test run:

```sh
grep -F '[ZomboidRangeSelect]' "$HOME/Zomboid/console.txt" | tail -30
```

- `no controller assigned at game start`: your character was mouse-controlled when the game began; switch to controller mode before testing. You may still assign it later in the session.
- `D-pad ... RT=...`: inventory page is receiving D-pad events and reports the right-trigger axis value.
- `RT selection started`: our range-selection hook ran.
- `RT released; selected items=N`: selection was committed.
- **No D-pad lines despite moving with D-pad:** the inventory page isn't receiving controller focus/events; check Steam Input and PZ controller activation. Lua cannot fix input that PZ doesn't route into this UI.

## Known risks / validation required

1. RT is read as the B42 analog `JoypadAxis1d.RightTrigger` (>0.25 on its -1..1 scale). The D-pad callback's controller ID is used even if the player gamepad association is not yet initialized.
2. Input handling depends on `JoypadAxis1d.RightTrigger:getValue`, `ISInventoryPage`, and `ISInventoryPane` hooks. Confirm against installed B42 files.
3. Stacked/collapsed inventory rows, switching bags, sorting while selecting and scrolling need in-game checks.
4. Verify transfer safety for favorites, equipped/heavy items, multi-player clients and mixed item stacks; vanilla context-menu transfer helpers are used.
5. Inventory-screen UI in icon mode is intentionally unsupported.
6. Other inventory/controller mods may override the same methods depending on load order.

## Publishing

Source is ready for a GitHub repository. `.github/workflows/ci.yml` checks syntax, runs Lua state tests and uploads the Workshop-shaped ZIP. To publish on Steam Workshop, set the appropriate Workshop ID in `workshop.txt` after the initial upload using the game's Workshop UI.

**License:** not yet selected; don't republish source as an open-source licensed mod until a license is added deliberately.
