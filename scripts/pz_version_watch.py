#!/usr/bin/env python3
"""Detect newly observed Project Zomboid client builds.

This does NOT prove in-game compatibility. It creates one review issue per
branch/build after the existing Lua test suite has passed.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

APP_ID = "108600"
BRANCHES = ("public", "unstable")
ISSUE_PREFIX = "[PZ compatibility]"


def read_builds(raw: str) -> dict[str, str]:
    # SteamCMD outputs Valve KeyValues, not JSON. Restrict discovery to
    # depots -> branches and a branch's immediate properties.
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|[{}]', raw)
    stack = []
    pending = None
    builds = {}
    for i, token in enumerate(tokens):
        if token == "{":
            if pending is None:
                stack.append(None)
            else:
                stack.append(pending)
            pending = None
        elif token == "}":
            if stack:
                stack.pop()
            pending = None
        elif token.startswith('"'):
            value = token[1:-1]
            if i + 1 < len(tokens) and tokens[i + 1] == "{":
                pending = value
            elif (len(stack) >= 3 and stack[-3:] == ["depots", "branches", stack[-1]]
                  and stack[-1] in BRANCHES and value == "buildid"
                  and i + 1 < len(tokens)):
                build = tokens[i + 1].strip('"')
                if build.isdigit():
                    builds[stack[-1]] = build
    if not builds:
        raise ValueError("No public/unstable build IDs found in SteamCMD output")
    return builds


def issue_title(branch: str, build: str) -> str:
    return f"{ISSUE_PREFIX} {branch} build {build}"


def gh(*args: str) -> str:
    return subprocess.check_output(["gh", *args], text=True).strip()


def notify(builds: dict[str, str]) -> None:
    for branch, build in sorted(builds.items()):
        title = issue_title(branch, build)
        # Exact title check against all issues including closed ones, to
        # avoid duplicate alerts on every daily run.
        results = json.loads(gh("issue", "list", "--state", "all", "--search",
                                f'in:title "{title}"', "--limit", "100",
                                "--json", "title,number"))
        if any(item["title"] == title for item in results):
            print(f"Already reported: {title}")
            continue
        body = (
            f"Steam published a previously unseen Project Zomboid **{branch}** "
            f"client build ID **{build}** (app {APP_ID}).\n\n"
            "The repository's Lua syntax and mocked controller tests passed "
            "in the version-watch workflow. **They do not run against the "
            "actual game's client code or establish compatibility.**\n\n"
            "Review the following integration points in the new game build:\n"
            "- [ ] `ISInventoryPage.onJoypadDown` and direction callbacks\n"
            "- [ ] `ISInventoryPane.doContextOnJoypadSelected`\n"
            "- [ ] `ISInventoryPane.update` and `prerender`\n"
            "- [ ] RT + D-pad selection, A context menu, X transfer, B clear\n"
            "- [ ] Inventory focus and pane switching\n\n"
            f"Workflow: {os.environ.get('GH_WORKFLOW_URL', 'manual execution')}\n"
            "Close after checking the mod in-game on this build."
        )
        print(f"Opening review issue: {title}")
        gh("issue", "create", "--title", title, "--body", body)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, nargs="?")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--notify", type=Path, metavar="JSON")
    args = parser.parse_args()
    if args.notify:
        builds = json.loads(args.notify.read_text())
        notify(builds)
    elif args.source:
        builds = read_builds(args.source.read_text(errors="replace"))
        print(json.dumps(builds, indent=2))
        if args.output:
            args.output.write_text(json.dumps(builds, indent=2) + "\n")
    else:
        parser.error("provide SteamCMD output or --notify builds.json")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        print(f"Version watch failed: {error}", file=sys.stderr)
        sys.exit(1)
