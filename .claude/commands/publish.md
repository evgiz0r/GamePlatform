---
description: Export the game to the web so it can be shared with a link.
---

Export for the web: **$ARGUMENTS**

1. Check whether Godot's web export templates are installed. If not, tell the user to open
   Godot and use **Editor → Manage Export Templates → Download and Install**, then stop.
   Do not try to download templates yourself.
2. Ensure an export preset named `Web` exists in `export_presets.cfg`. Create one if
   missing.
3. Export to `export/web/index.html`:

```bash
godot --headless --path . --export-release "Web" export/web/index.html
```

4. Tell the user the files are in `export/web/` and that the game needs to be served over
   HTTP — opening `index.html` directly from disk will not work. Suggest:

```bash
python -m http.server 8000 --directory export/web
```

Do not upload the build anywhere or publish it to any host. If the user wants it online,
explain the options and let them choose and do it themselves.
