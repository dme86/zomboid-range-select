# Zomboid Range Select

**v0.1.5 prototype** for Project Zomboid Build 42 (tested in automated Lua mocks, not yet confirmed in the live game).

The mod is a new, independent implementation. It does not contain the third-party Workshop mod's source code.

## Controls

- Hold **RT + D-pad up/down** in a focused inventory or loot list to mark a range.
- Release RT to keep the selection. Hold RT again somewhere else to add a second range.
- Move back towards the starting point while holding RT to shrink only the current range.
- **A**: regular context menu if nothing selected; otherwise context menu for selected items.
- **X**: transfer selected items using vanilla transfer handlers.
- **B**: clear the selection while selected; otherwise behaves normally.

## What changed in v0.1.5

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
- \`v0.1.4 polling selection hooks installed\`: the Lua file was evaluated.
- \`registered game-tick fallback\`: the independent game-tick callback was registered.
- \`inventory polling active\`: inventory callbacks/game tick executed, and an inventory pane received controller focus.
- \`RT down\`, \`selected=N\`, \`RT up\`: trigger read and range selection working.

If the log only contains the initial hook messages, **check whether a game world and the controller-focused inventory were actually reached**. The initial messages are also printed during menu Lua initialization.

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
find Contents -type f -name '*.lua' -exec luac -p {} \;
\`\`\`

CI runs syntax and mock tests and creates a ZIP artifact. Live PZ 42.21 and macOS 8BitDo controller testing remain outstanding.

## License

No license selected yet; GitHub hosting alone does not grant others permission to redistribute the code.
