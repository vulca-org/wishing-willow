---
description: Print the statusLine snippet to paste into your Claude Code settings
allowed-tools: []
---

The hooks are already running — they started the moment this plugin was enabled.
What's missing is the display.

Claude Code plugins cannot ship a `statusLine`; it has to live in the user's own
settings file. So print the snippet and let the user paste it themselves. Do not
edit their settings file for them, and do not offer to.

Print exactly this, with no preamble beyond a single line of context:

---

**Add this to `~/.claude/settings.json`** (or your project's `.claude/settings.json`):

```json
{
  "statusLine": {
    "type": "command",
    "command": "node \"${CLAUDE_PLUGIN_ROOT}/statusline/willow-status.mjs\"",
    "padding": 1
  }
}
```

If you already have a `statusLine` key, replace it — Claude Code supports only one.

**The path contains the plugin version.** After `/plugin update willow`, that
directory changes and the status line goes blank. Re-run `/willow:setup` and
paste the new path. (Tracked as a known wart, not a mystery.)

Then start a new session, or run any prompt: the status line updates when the
next assistant message arrives.

**What you'll see**

```
你批准的  <your prompt, verbatim>
我读成了  <how the model says it read you>
```

or, when the model didn't declare anything:

```
你批准的  <your prompt, verbatim>
⚠ 本轮未声明
```

The two rows are never compared for you. Whether they agree is yours to judge —
that is the entire design.

---

After printing, say one sentence: the hooks work without this step, but nothing
is visible until it's done.
