# Wishing-Willow

**Shows what the model thinks you asked, next to what you actually said.**

```
你批准的  找这类问题的通用逻辑，要可复用的方案
我读成了  ⚠ 审计那个仓库的检查表与 spec，找漂移证据
```

It does not score the two. It does not block anything. Nothing leaves your machine.
Whether they agree is yours to judge — that is the whole design.

---

## The problem

You ask for one thing. The model fills in the parts you didn't say, using its own
defaults, and starts working on something adjacent. Its reply reads perfectly
reasonable, so you don't notice — sometimes for several turns.

This is not hypothetical. This plugin exists because it happened three times in
the conversation that produced it. The first time, the request was "find the
general logic behind this class of problem"; the model read it as "audit this
specific repository for evidence" and spent two turns doing that. The user caught
it on turn three. **Two turns, wasted, on work nobody asked for.**

Claude Code already has an answer for this — **plan mode**, whose own
documentation gives almost exactly this example: you ask for two lines of
middleware, the model plans a pipeline rewrite, and the plan surfaces the gap
before the first edit.

But plan mode triggers on **how much will change** — three or more files, a schema,
security-sensitive code — and the official guidance says to skip it for
"tiny one-file edits or read-only questions." All three drifts above happened
during **read-only investigation**. Zero files changed. Nothing to trigger on.

Willow covers that gap, and only that gap. It is not a replacement for plan mode.

## Install

**1 — the plugin** (hooks start working immediately)

```
/plugin marketplace add vulca-org/wishing-willow
/plugin install willow@wishing-willow
```

**2 — the display** (a plugin cannot ship a `statusLine`; this step is unavoidable)

```
/willow:setup
```

It prints a snippet for your `~/.claude/settings.json`. **It does not edit your
settings for you.** The snippet resolves the installed path at runtime, so a
plugin update does not blank your status line.

**3 — macOS menu-bar reader** (optional) — see [`macos/`](macos/).

## Requirements

- Claude Code
- **Node.js** on `PATH` — the hooks are `.mjs` files invoked as `node …`.
  Claude Code ships as a self-contained binary, so having Claude Code is *not*
  evidence you have Node. Check with `node --version`.
- Tested on macOS. **Windows is untested** — the hook config uses exec form, which
  should be portable, but nobody has run it there.

If Node is missing, the hooks fail as non-blocking errors: Willow won't work, but
nothing else breaks.

## How it works

| | |
|---|---|
| `UserPromptSubmit` | Writes your prompt **verbatim** to `~/.claude/willow/<session>.json`. For substantial requests, asks the model to declare how it read you. Short replies, slash commands and acknowledgements are skipped. |
| `Stop` | Reads the transcript of the turn that just ended and looks for the declaration at the top of the model's messages. Found → records it, along with the short tag. Not found → leaves it `null`. Also prunes state files whose process is gone and that nobody has touched for a week. |
| `statusLine` | Prints the two rows. |

`Stop` hands the hook a field called `last_assistant_message`, which sounds like
the reply and is not: it is the *last* message of the turn. A turn that calls
tools ends with whatever prose followed the final tool result. The first real
turn this plugin ever saw declared correctly in its opening message and ended
fifteen messages later, so reading that field recorded the declaration as
absent. The transcript is read instead, bounded to the turn — scanning past the
turn boundary could surface an earlier turn's declaration as this one's, which
is worse than reporting none.

**The asymmetry is the point.** The `prompt` field is written only by the capture
hook, from the text you submitted. The model has no path to it — not "shouldn't
rewrite it", *cannot reach it*. A declaration the model writes goes in a separate
field, and the absence of that field is itself the signal.

There is deliberately no `status` field. `declared` vs `undeclared` is derived by
whoever reads the file, from whether `decode` is empty. A status the hook could
write is a status that could be wrong while the declaration is missing — which
would restore exactly the silence this plugin exists to break.

Three things never reach the model as a request to decode: a slash command, a
pure acknowledgement, and **an envelope the user did not type**. Claude Code
delivers background-task notifications and similar system messages through the
same hook; on 2026-09-12 one of them made the plugin ask the model to declare
what the user had approved when the user had said nothing at all.

Quoting a declaration is not making one, either. Lines inside a code fence, a
blockquote, or an indented block are skipped — the model pasting an example of
the two rows must not be recorded as this turn's declaration. That bug corrupted
a measurement the same day it appeared.

There is a third state, and it exists because of a real failure. The hook input
field carrying your prompt is `prompt`. The documentation says `user_prompt`.
This plugin was written from the documentation, so for its first day it ran on
every turn, found no such field, exited 0, and captured nothing — and a plugin
that silently does nothing looks exactly like a plugin reporting no problems.
Both names are now accepted, and the record carries `promptField` naming the one
that matched. `prompt` and `promptField` both null means **the hook could not
read your input** — the reader says so instead of drawing a blank row.

## What it cannot do

**It never colours a turn green.** Green reads as "checked, fine", and nothing
here checks. The model may mark its own decode line with ⚠ when it thinks the two
rows disagree; the reader forwards that mark and computes nothing of its own.

**It cannot tell whether the two rows actually agree.** That's semantic, and asking
the model to judge its own decoding means asking it to use the same defaults that
produced the drift. It would report "aligned" and you'd be worse off than with no
tool at all.

**It cannot detect a dishonest declaration.** A model can write a decode line that
echoes your words while doing something else. Only you can catch that. This plugin
makes the declaration visible; it does not verify it.

**It changes the thing it measures.** The reminder asks the model to state how it
read you *before* it answers. Some of the declaration rate — 9 turns out of 9 in
the first day of real use — is very likely the model reading the request more
carefully because it has to write the line. That is probably a good thing, but it
means this is an intervention, not just an instrument, and **the baseline is gone
for good**: there is no longer a way to measure how often the model would have
drifted without it. Any later claim about how much drift there is has to say
which side of that line it was measured on.

**It has no idea whether you're drifting productively.** Plenty of turns go somewhere
you didn't specify and that's fine. The two rows are information, not a verdict.

## Privacy

No network calls. No telemetry. No model calls. State stays in
`~/.claude/willow/`, one small JSON per session, and nothing else reads it unless
you install the macOS app. Delete the directory any time; the plugin recreates it
on the next turn.

Hooks that mishandle input get in the way of real work, so every failure path here
exits 0 silently — malformed input, missing fields, unwritable directory. The
capture hook blocks your Enter key until it returns, so it does one cheap thing
and gets out of the way.

## Tests

```bash
node tests/replay/run.mjs      # behaviour
node tests/contract/run.mjs    # registration
node tests/runtime/run.mjs     # field names
```

Three gates, because this plugin has now failed twice in ways a single gate
structurally could not see.

**replay** runs the hooks against recorded turns and checks the resulting state:
a real drift (declaration absent), a declared-but-drifting turn, a real aligned
turn, a declaration buried before a dozen tool calls, an earlier turn's
declaration that must *not* be reused, two bypass paths, malformed input, an
English declaration, the legacy field name, and an unrecognised one. One case
pins the exact key set of the state file, so no field that scores the two rows
can ever be added accidentally. The bypass
thresholds are calibrated against actual prompts — including the fact that a
Chinese request carries roughly 2.5× the information of a Latin one at the same
character count, so weighing characters directly gets it backwards.

**contract** executes the command exactly as `hooks.json` spells it. Replay
spawned the scripts directly, which meant `hooks.json` itself was never tested —
and it was wrong: it used a `command` + `args` pair, `args` is not part of the
schema, and the field was silently ignored. Every replay case stayed green while
the plugin had never once run inside Claude Code.

**runtime** reads the payload field names out of the installed `claude` binary
and feeds the hook using *those* names. Fixtures written from the docs cannot
catch the docs being wrong, because the code was written from the same page.
With no `claude` on the machine it prints SKIP and counts it separately — a skip
is not a pass.

## License

MIT
