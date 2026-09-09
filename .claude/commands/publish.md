---
description: Export the game to the web so it can be shared with a link.
---

Export for the web: **$ARGUMENTS**

1. Check whether Godot's web export templates are installed, **for the standard build**.
   The .NET/mono build cannot export to Web at all, and installs its templates under a
   separate version folder the standard build cannot see. If they are missing:
   - **On the user's own machine**, tell them to open the standard editor and use
     **Editor → Manage Export Templates → Download and Install**, then stop. Do not
     download a 1.2 GB archive onto someone's PC unasked.
   - **In a remote session** (Claude Code on the web; `GODOT` points into `~/.cache`),
     run `tools/setup_godot.sh --templates`. It slices just the web templates out of the
     archive (about 10 MB) into the folder Godot looks in. The session-start hook already
     does this, so normally there is nothing to do.
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

5. GitHub Pages serves `docs/` from the **default branch**. A build committed on a feature
   branch is not online until it is merged, so if the user wants to "test online", the
   build has to land on `main`. Do that on `main` itself or merge straight after.
6. A remote session cannot fetch `*.github.io` (the container's proxy refuses it), so do
   not claim the site is live: say the build is pushed and ask the user to open it.

Do not upload the build anywhere or publish it to any host. If the user wants it online,
explain the options and let them choose and do it themselves.
