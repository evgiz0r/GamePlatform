# Ideas — things to build one day, not today

A parking lot for concepts about this kit. Nothing here is scheduled or in progress.
Adding a line costs nothing; it is a thought, not a promise. When one gets built, move
its notes to wherever the work lives and delete the line.

If you are the AI: read this before proposing new features, so you do not re-pitch what
is already parked, and when the person mentions something new that is not being built
right now, offer to add it here rather than letting it get lost in the chat.

## Games and content

- **Dialog as a shared system.** One game now has its own text box with portraits and
  multiple-choice answers. When a second game needs one, lift it out of that game into
  something both can use, rather than copying it.
- **Memory games.** Match pairs, repeat the sequence, that family.
- **2D open world.** A big map you wander instead of one screen.
- **3D open world.** "2D open world" above, but in 3D: `GameMode3D` exists now
  (`shell/game_mode_3d.gd`, see `game/drop/`), so this is the open-world part. Biggest
  item on this list.
- **Card games and card assets.** Deck, hand, table; and the art to go with it.
- **Game flow in open worlds.** State machines, a database of characters, states and
  dialogs. How do people actually structure this? Research first, then decide.
- **Open world of gambling.** You wander around and play mini games with bets. Every
  person you meet has their own riddle or game. Somewhere between math puzzles and
  spotting the scammer's trick. Leans on "2D open world" and "in-game dialog" above.
- **Dressing and clothes.** An open world where you start in bad clothes. People you
  meet present themselves and what they wear, and you pick what you want: sometimes you
  buy it, sometimes they give it to you for a reason. You see yourself wearing it, and
  everyone else wearing theirs. A visual game first. Needs layered outfit art, which the
  kit does not have today (see "Hand-drawn input" below).

## Platform and tooling

- **Tracking verified music.** Which tracks are confirmed CC0 vs CC-BY, where they came
  from, what has been checked. Today this lives loosely in `assets/CREDITS.md` and a
  note in `assets/INDEX.md`.
- **Skills for recurring tasks and concepts.** Whenever something is done twice, or the
  AI notices it is new, it should suggest tracking it (as a skill, a doc, or whatever
  fits) so the next time is easier. This file is the first step of that.
- **Camera integration.** Use the player's webcam as an input or a texture.
- **Multiplayer, my computer as the server.** Something simple: one-versus-one.
- **Hand-drawn input.** Let the player draw their own assets online, or have the first
  interaction ask about and suggest assets instead of assuming the kit's art.
