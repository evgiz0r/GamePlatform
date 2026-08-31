---
description: Change how the game looks — swap the color palette or restyle the world.
---

Change the look: **$ARGUMENTS**

The whole kit is palette-driven, so this is usually a small change with a big effect.

**If the request matches an existing palette** (`neon_candy`, `ice`, `sunset`, `jungle`,
`haunted`) — set it as the default in `SaveData` and tell the user they can also cycle it
from the menu button.

**If it does not** — add a new palette to `shell/autoload/palette.gd`. This is the one file
inside `shell/` you may edit, and only to add a palette entry. Keep all nine roles:
`bg bg_alt ink player friend hazard warn prize accent`.

Choose colors that stay bright against a dark background. Test that `hazard` and `prize`
are clearly distinguishable — that distinction is load-bearing for gameplay, not decoration.

**If they want shapes changed rather than colors**, edit the `Blob` shape and radius values
in the game file, not the shell.

Afterwards, say what changed in one sentence. If a new palette was added, name it so they
can ask for it again.
