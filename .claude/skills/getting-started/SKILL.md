---
name: getting-started
description: 'First-time setup and onboarding for someone who has just cloned this kit — what to download, what to click, how to run the project, how to enable playtesting, and how to fix the usual first-run problems. Use when the user is new, when nothing is installed yet, when Godot will not open or run the project, or when they ask how to begin.'
---

# Helping someone start from nothing

Assume the person you are helping has never used Godot and may never have used a terminal.
Give them **one instruction at a time** and wait. Do not paste a ten-step list — people
lose their place, and a stalled setup is the most common reason a kit like this gets
abandoned.

Check what is already installed before telling anyone to install anything.

## What they need

Three things. Nothing else.

### 1. Godot 4 — the game engine

Download from **https://godotengine.org/download**

Tell them to get the **standard** version, *not* the ".NET" / "Mono" one. The .NET build
is for C# and this kit is GDScript. Downloading the wrong one is the single most common
setup mistake.

- **Windows** — a `.zip`. Unzip it anywhere (Downloads is fine). Inside is
  `Godot_v4.x-stable_win64.exe`. That file *is* Godot; there is no installer and nothing
  to run as administrator. They may want to right-click → *Pin to Start*.
- **macOS** — a `.zip` containing `Godot.app`. Drag it to Applications. On first launch
  macOS will say it cannot verify the developer: **right-click the app → Open**, then
  *Open* again in the dialog. Double-clicking will just refuse, which people read as
  "broken".
- **Linux** — a `.zip` with a binary. `chmod +x` it and run it.

### 2. An AI coding tool

**Claude Code** — https://claude.com/claude-code. This kit is tuned for it: the `/`
commands and skills in `.claude/` only work there.

### 3. Git

Needed to clone the kit, and it is the undo button for everything afterwards.
https://git-scm.com/downloads. On macOS, running `git --version` once in Terminal offers
to install it.

## Opening the project — the exact clicks

1. Launch Godot. It opens the **Project Manager**, a list of projects (empty at first).
2. Click **Import** (top left).
3. Click **Browse**, navigate to the cloned `GamePlatform` folder, select
   **`project.godot`**, and click **Open**.
4. Click **Import & Edit**.

Godot opens the editor and imports assets — a few seconds the first time.

5. Press **F5** to run. (On some Macs, **Fn+F5**. There is also a ▶ play button, top right.)

A window appears with a menu and a game called *dodge*. Arrow keys or WASD to move.

**Tell them to play it for ten seconds.** It sets the reference point for what "working"
means, so later they can tell you "it's not doing X like dodge does".

## Enabling self-play (worth doing)

The kit can play its own games headlessly and report bugs — but it needs to know where
Godot is. Without this, `tools/playtest.sh` fails and you are building blind.

Ask them for the path to their Godot binary, then:

- **macOS / Linux**: `export GODOT="/path/to/godot"` (add it to `~/.zshrc` or `~/.bashrc`
  to make it stick)
- **Windows (Git Bash)**: `export GODOT="/c/Users/<name>/Godot/Godot_v4.x-stable_win64.exe"`
- **Windows (PowerShell)**: `$env:GODOT = "C:\path\to\Godot_v4.x-stable_win64.exe"`

Verify it immediately:

```bash
tools/playtest.sh dodge smart 10
```

A report means it works. Do not move on until it does — everything downstream depends on it.

## Their first game

Once *dodge* runs, ask what they want to make and run `/new-game <their idea>`.

If they have no idea, do not present a menu of genres. Ask **"what's your favourite
animal?"** and build something around it. A game starring their answer beats a better
game about nothing.

## When it goes wrong

| What they see | What it is |
|---|---|
| "This project was made with a newer version" | Their Godot is older than 4.x. Update it. |
| Godot asks about C# / a solution / .NET | They downloaded the .NET build. Get the standard one. |
| macOS: "cannot be opened, unidentified developer" | Right-click → Open, then Open again. |
| Project Manager shows nothing after Import | They selected the folder, not `project.godot`. |
| F5 does nothing | Fn+F5 on Mac, or click the ▶ button. |
| Game window opens then closes instantly | A script error. Check Godot's **Output** panel at the bottom, and read the error to them. |
| `tools/playtest.sh`: "Godot not found" | `GODOT` is unset or wrong. Re-check the path. |
| Sounds are silent | Normal if a sound is missing; the playtest report says which. |
| Web export complains about templates | **Editor → Manage Export Templates → Download and Install**. Roughly 500 MB, one time. |

## Things worth telling them early

- **"Undo the last change" always works.** This is a git repo. Nothing is ever lost, and
  a broken game cannot break the menu — worst case they land back on a working main menu.
- **Commit when a game is good.** It gives them a point to fall back to. Offer to do it.
- **Their game files live in `game/`.** Everything else is machinery they can ignore.
- **`GAME.md` is theirs.** It is the design in their own words and it outranks the AI's
  taste. Encourage them to write in it badly rather than not at all.
- **AI coding costs money per session.** Say this once, plainly, early. It is better than
  them discovering it later.

## Tone

The person you are onboarding may be a parent working alongside a child. Keep instructions
short and free of jargon, celebrate the moment the first game runs, and let them steer.
The goal of the first session is not a finished game — it is that something they described
appeared on screen.
