# Zomboid Range Select

**v0.1.17 controller range selection** for Project Zomboid Build 42, verified in the live game on macOS with an 8BitDo controller.

The mod is a new, independent implementation. It does not contain the third-party Workshop mod's source code.

## Controls

- Hold **RT + D-pad up/down** in a focused inventory or loot list to mark a range.
- Release RT to keep the selection. Hold RT again somewhere else to add a second range.
- Move back towards the starting point while holding RT to shrink only the current range.
- **A**: regular context menu if nothing selected; otherwise context menu for selected items.
- **X**: transfer selected items using vanilla transfer handlers.
- **B**: clear the selection while selected; otherwise behaves normally.

## What changed in v0.1.6

**No D-pad hooks.** The mod now polls the native inventory cursor (\`joyselection\`) and the RT analog value as the inventory UI updates. There is an independent \`OnTick\` fallback in case a UI update hook is replaced by another mod. This avoids the previous dependency on \`ISInventoryPage:onJoypadDirUp/Down\` callbacks.

It logs a single \`inventory polling active\` line once an actual controller-focused inventory pane is detected, then logs RT press, selection changes and release. No global controller-scanning debug loop outside gameplay.

RT is never remapped; outside an active inventory/loot pane, its vanilla combat actions remain untouched.

## macOS install/update (fish shell)

Quit PZ completely, then:

\`\`\`fish
set SRC (mktemp -d)
git clone --depth 1 https://github.com/dme86/zomboid-range-select.git "$SRC/repo"
ditto "$SRC/repo/Contents/mods/ZomboidRangeSelect" "$HOME/Zomboid/mods/ZomboidRangeSelect"
\`\`\`

Enable the mod in your save and disable any other controller multi-select mod. Restart PZ.

## Troubleshooting

To view only the relevant lines:

\`\`\`fish
grep -F '[ZomboidRangeSelect]' ~/Zomboid/console.txt
\`\`\`

Expected after entering a game with controller-focused inventory:
- \`v0.1.17 vanilla multi-item menu and range selection installed\`: the Lua file was evaluated.
- \`registered game-tick fallback\`: the independent game-tick callback was registered.
- \`inventory polling active\`: inventory callbacks/game tick executed, and an inventory pane received controller focus.
- \`RT down\`, \`selected=N\`, \`RT up\`: trigger read and range selection working.

If the log only contains the initial hook messages, **check whether a game world and the controller-focused inventory were actually reached**. The initial messages are also printed during menu Lua initialization.

## World lifecycle reliability

The old implementation installed its UI method wrappers and a file-local
tick callback while Lua was loading in the main menu. This version keeps
event callbacks in the persistent global `ZRS` table and registers
`OnGameStart`, `OnCreatePlayer`, `OnPlayerUpdate` and `OnTick`.
It checks whether the UI class methods were subsequently replaced by the
game or another mod and reinstalls the same wrappers, without stacking them.

These are defensive fixes, not proof of a specific cause on macOS.
Look for `OnGameStart world entered`, `DIAG OnTick event fired` and
`DIAG OnPlayerUpdate event fired` after loading a saved game.

## One diagnostic test in PZ 42.21

After installing and restarting, **load the actual game save**, not just the main menu.
Open the inventory with your controller, move the D-pad two rows, hold RT and move
two more rows, then release RT. Extract only these lines:

```fish
grep -F '[ZomboidRangeSelect]' ~/Zomboid/console.txt | tail -50
```

Diagnostic messages are one-shot per distinct state, so normal navigation will not
flood the console. Their meaning:

- `DIAG Events.OnTick executing`: the registered game-tick callback actually runs.
- `DIAG ISInventoryPane:update reached` or `prerender reached`: Lua UI hooks execute.
- `DIAG inventory gate: ...`: shows the precise readiness condition that is blocking selection.
- `DIAG RT axis held`: the controller's analog RT input is actually being read.
- `inventory polling active`, `RT down`, `selected=`: state machine reached.

No `DIAG` lines beyond `hooks installed` after loading and navigating the inventory
means the Lua hooks or registered events are not being invoked in the running game;
in that case we'll examine mod load timing or overridden functions, not the 8BitDo mapping.

## Tests

\`\`\`sh
lua tests/test_core.lua
lua tests/test_client_mock.lua
lua tests/test_runtime_probe.lua
find Contents -type f -name '*.lua' -exec luac -p {} \;
\`\`\`

CI runs syntax and mock tests and creates a ZIP artifact. The v0.1.17 behavior has also been confirmed in live PZ 42.21 on macOS with an 8BitDo controller.

## License

No license selected yet; GitHub hosting alone does not grant others permission to redistribute the code.

## Independent runtime probe (v0.1.7)

The earlier log showed that registering `OnTick` is **not proof** that the callback actually ran. This build does not guess at RT mapping. It installs an independent diagnostic in `common/media/lua/client`, `42/media/lua/shared`, `42/media/lua/client`, and `42/media/lua/server` to distinguish Lua loading contexts. The client probe registers `OnFETick`, `OnGameStart`, `OnCreatePlayer`, `OnTick`, `OnPlayerUpdate`, `OnPreUIDraw`, `OnPostUIDraw`; every event logs **once** on first invocation. The server probe similarly observes world/server load. These probes don't intercept controller buttons or change inventory selection.

**One test:** Restart PZ after installing v0.1.7, enter your save, open inventory with controller, move D-pad, hold RT and move D-pad again. You may exit the game afterwards, but the log is readable without exiting.

```fish
grep -E 'ZRS-PROBE|ZomboidRangeSelect' ~/Zomboid/console.txt | tail -80
```

Interpretation:

- `COMMON CLIENT FILE LOADED`, `SHARED FILE LOADED`, `CLIENT FILE LOADED` show **which script roots** PZ loaded, not proof of gameplay activity.
- `CLIENT EVENT FIRED OnFETick` proves the frontend event dispatched; `CLIENT EVENT FIRED OnTick` / `OnPlayerUpdate` proves world callbacks in that client Lua environment.
- `SERVER FILE LOADED` shows world/server file loading (this is dependent on single-player server setup and may not appear).
- If `OnFETick` fires but no world event fires after loading a game, focus on the **frontend-to-world Lua lifecycle and mod activation**, not controller mapping.
- If world events fire but no `DIAG ISInventoryPane:update reached` appears, focus on **UI hook lifecycle/overrides**, not RT mapping.

Keep in mind the mock only tests that probe functions *would* fire when invoked; the actual PZ runtime is the source of truth.

## No-log debugging: v0.1.8 HUD

Prior tests demonstrated that the Mac game process keeps console.txt and DebugLog.txt open without necessarily appending later world events while the player is active. Absence of new log output does **not** prove that the controller or UI events are failing. The separate `ZZ_ZRS_RuntimeProbe.lua` now draws four small yellow status lines at the upper left in the main menu and in gameplay when the post-UI event is dispatched. It includes live player presence, controller bind ID, RT analog value, inventory cursor/row count/controller focus and which lifecycle events fired. It does not modify input and is only a temporary diagnostic.

**Next test:** Fully restart PZ with this version, look for `ZRS DEBUG v0.1.8` in the main menu, load the save, open the inventory and hold RT while pressing D-pad up/down. Take a screenshot with the overlay visible. If the overlay appears only in the main menu, tell us; this distinguishes a UI event / Lua lifecycle problem from analog trigger reading. If it appears in-game, its fields identify the next fix. No terminal logs needed for this test.

Note: the HUD drawing API is exercised in Lua mocks, but not yet in real PZ 42.21 on macOS; CI success alone does not verify in-game rendering.

## v0.1.10 correction: vanilla D-pad navigation preserved

Version 0.1.9 briefly introduced an intrusive directional-navigation override and a global inventory auto-collapse guard, based on an unverified hypothesis that PZ was collapsing the loot window normally. That change failed CI and has been **fully reverted**. The vanilla `ISInventoryPage:onJoypadDirLeft`/`onJoypadDirRight` and `collapseNow` methods are not hooked or replaced by this version. The RT multi-selection code is otherwise unchanged from the last known green build (v0.1.8).

The yellow HUD now shows a short **read-only** `Windows` line: `focus=PERSONAL/LOOT/NONE/OTHER`, plus each panel's `collapsed` and `joyfocus` values. These measurements distinguish a focus switch from an actual collapse and help isolate the behavior introduced in the presence of the mod. No UI behavior is modified by the probe. Test by pressing D-pad left/right once in each pane and capturing the HUD before/after.

## v0.1.11: A menu and directional D-pad

PZ 42's native A button invokes `ISInventoryPane:doContextOnJoypadSelected`. The mod now handles an existing multi-selection **at that entry point**, passing all selected actual items to `ISInventoryPaneContextMenu.createMenu`. The HUD includes a last-menu count, source pane and result to distinguish actual multi-item actions from just visual highlighting. A without an existing selection is vanilla. Selection is per pane: selecting in personal inventory and then pressing A on loot does not combine unrelated containers.

In inventory focus only, D-pad **left means personal** and **right means loot**; pressing the direction of the current pane is a no-op rather than toggling. Both windows are re-expanded while joypad focus is on inventory; mouse auto-collapse stays vanilla outside inventory focus. This is a focused compatibility override, not a rewrite of controller movement.

Test in a loaded save with 2+ selected items in **one pane**, release RT and press A in that same pane. The HUD should say `Menu: 2` (or more) and the menu should offer relevant multi-item options. Then press D-pad left/right and check the windows remain expanded. Automated mocks verify routing; actual PZ 42.21 remains the acceptance test.

## v0.1.12

Adds an explicitly labelled first context-menu option `ZRS: N markierte nehmen` for loot or `ZRS: N markierte verschieben` for carried items when 2+ items are selected. Delegates to native PZ item transfer callbacks. Vanilla menu item-type options are still shown. PZ may reject protected/favorited items according to its own validation. The HUD now shows `bulk option added` rather than simply `created` and a `Nav:` line describing whether a LEFT/RIGHT event arrived and where the focus ended up. During controller inventory focus, the native mouse-away collapse is suppressed; it remains enabled outside inventory focus. This build still needs live validation on B42.21.

## v0.1.17

The live-tested controller flow now keeps the current inventory pane open while an RT selection is pending. Left/right D-pad input is ignored only during that pending selection and is delegated back to vanilla as soon as the marks are cleared. This removes the asymmetric window disappearance without globally overriding inventory collapse or focus behavior.

Pressing **A** with marked items now opens PZ's normal context menu with the complete selected-item list. The redundant custom `ZRS: N markierte ...` entry has been removed, so native actions such as **Nehmen** and **Verschieben nach** apply to the selection. **X** directly transfers all marked items, including when pressed before RT is released; **B** clears the marks.

The selection overlay no longer changes PZ's shared stencil buffer. Its highlight rectangles are clipped numerically, preventing one inventory pane's rendering from clipping or hiding the other pane.
