---
description: Export the game to the web so it can be shared with a link.
---

Export for the web: **$ARGUMENTS**

1. Check whether Godot's web export templates are installed, **for the standard build**.
   The .NET/mono build cannot export to Web at all, and installs its templates under a
   separate version folder the standard build cannot see. If they are missing, tell the
   user to open the standard editor and use **Editor → Manage Export Templates → Download
   and Install**, then stop. Do not download templates yourself.
2. Ensure an export preset named `Web` exists in `export_presets.cfg`. Create one if
   missing.
3. Build with the script — do not call the export by hand. It also repairs the manifest
   Godot writes, which is missing the 192px icon Chrome wants before it will offer a real
   install rather than a plain home-screen shortcut:

```bash
tools/publish_web.sh
```

4. The build lands in `docs/`, which is what GitHub Pages serves. Commit and push it. To
   check it first, it must be served over HTTP — opening `index.html` from disk will not
   work:

```bash
python -m http.server 8000 --directory docs
```

Do not upload the build anywhere or publish it to any host. If the user wants it online,
explain the options and let them choose and do it themselves.
