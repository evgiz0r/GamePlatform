# reference

Finished games parked out of the menu. Each folder is a complete game exactly as it was
under `game/`: code, scene and design, kept for reading, borrowing from and bringing back.

Godot ignores this folder (`.gdignore`), so nothing here is compiled, imported, exported or
listed on the menu. The menu only ever scans `game/`, so parking a game is just moving its
folder, and un-parking it is moving it back:

```bash
git mv reference/<name> game/<name>
```

Nothing else needs updating. The scene inside still points at `res://game/<name>/<name>.gd`,
which is right again the moment it is back.
