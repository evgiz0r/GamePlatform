---
name: getting-started
description: First-time setup and onboarding for someone who has just taken a copy of this kit — what to install, how to run it, how to make their first game, and how to fix the usual first-run problems. Use when the user is new, when nothing is installed yet, when Godot will not open or run the project, or when they ask how to begin.
---

# Somebody new is here

They want a game they made. They do not want a tour of the kit. Everything below serves
getting them to a playable game of their own as fast as possible.

**Tone:** they may not be a programmer. Never assume they know what a scene, a node or an
export template is. One instruction at a time, and wait.

## 1. Can they run it at all?

Two things must be true:

- **Godot 4 is installed** — the **standard** build, *not* the .NET/mono one. The mono
  build cannot export to the web at all and rewrites `project.godot` with C# settings this
  project has no use for. If they have the wrong one, say so plainly; it is a five-minute
  fix and it saves an hour later.
- **They can open the folder in Godot** and press **F5**.

If `GODOT` is set in their environment, `tools/playtest.sh` works and you can check things
yourself. If it is not, ask them for the path to their Godot binary and tell them to set
it — without it you are blind and every claim you make about their game is a guess.

Common first-run problems:

| What they see | What it is |
|---|---|
| Godot hangs on first open | It is importing assets. About ten seconds, once. |
| "No main scene" | They opened the wrong folder. It must be the one with `project.godot`. |
| A game runs but is silent | A missing sound file. Harmless; the playtest report names it. |
| Export fails on templates | Editor → Manage Export Templates → Download and Install. |

## 2. Show them it works

Run whatever game is already here — `tools/playtest.sh` with no arguments picks one — and
have them press **F5** and play it for ten seconds. That is not a demo, it is a baseline:
later they can say "it is not doing X like that one does" and you will both know what they
mean.

If `game/` is empty, skip this and go straight to making theirs.

## 3. Make theirs

Ask what they want. Take the first answer, however silly — it is their game.

Then run `/new-game <their idea>`, which will pin the design down with a couple of
questions, write it into `game/<name>/GAME.md` in **their** words, build it, and playtest
it before handing it back.

## 4. Tell them the four things that matter

Not the whole kit. These four:

- **Just say what you want.** "Make the fish faster", "add a shark", "make it icy".
- `/add <thing>` — one enemy, powerup or rule.
- `/look <style>` — changes the colours and mood.
- `/publish` — exports it to the web so they can send someone a link.

Then stop talking and let them play.

## Working with a kid

This kit was built for a parent at the keyboard and a child supplying the ideas. Two things
make that work far better:

- **Let the child answer the design questions.** Their answer wins, even when it makes a
  worse game. Ownership is the point.
- **Change one thing at a time and play it immediately.** The loop between saying something
  and seeing it is the whole experience.
