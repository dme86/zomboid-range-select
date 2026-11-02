# Zomboid Range Select

Controller-friendly multi-selection for Project Zomboid Build 42.

## Controls

- Hold **RT** and move D-pad up/down to mark a continuous range.
- Release RT, move elsewhere, then repeat to add another range.
- Press **A** for the normal Project Zomboid multi-item context menu.
- Press **X** to transfer all marked items immediately.
- Press **B** to clear the selection.

Pending selections keep both inventory panes open and prevent accidental
left/right pane switching. Version 0.1.18 removes the development HUD, probe
scripts and console diagnostics used while the controller integration was
being tested.

## Local installation

Copy `Contents/mods/ZomboidRangeSelect` to:

```text
~/Zomboid/mods/ZomboidRangeSelect
```

Enable **Zomboid Range Select** in the game's Mods menu and reload the save.

## Steam Workshop

The repository root is a complete Project Zomboid Workshop staging folder:

```text
ZomboidRangeSelect/
├── Contents/mods/ZomboidRangeSelect/
├── preview.png
└── workshop.txt
```

Copy the whole folder to `~/Zomboid/Workshop/ZomboidRangeSelect`, start the
Steam version of Project Zomboid, and choose **Workshop → Create and update
items**. Keep the first upload private while testing. Project Zomboid writes
the assigned Steam item ID into `workshop.txt`; preserve and commit that ID so
future uploads update the same item.

GitHub Actions also produces a ready-to-upload `ZomboidRangeSelect.zip`
artifact for every push.

## Tests

```sh
find Contents -type f -name '*.lua' -exec luac -p {} \;
lua tests/test_core.lua
lua tests/test_client_mock.lua
```

## Automatic game-version monitoring

The separate [Project Zomboid version watch](.github/workflows/zomboid-version-watch.yml)
workflow runs daily at 07:17 UTC or manually via GitHub Actions. It reads
**client** app 108600 Steam build IDs (public/unstable), runs the existing
Lua syntax and mocked-controller tests, and opens one GitHub issue for each
previously unseen branch/build ID. Closed issues are also considered to avoid
repeat alerts. The initial run will create review issues for current builds.

**Important:** a passing workflow does *not* prove compatibility with the new
game release: Steam metadata supplies build IDs, not the changed client Lua
APIs. Each issue includes an explicit manual in-game validation checklist.
The workflow fails rather than silently reporting success if Steam metadata
cannot be parsed. No Steam account credentials or game downloads are needed.

Issues require GitHub Actions to have permission to create repository issues.
