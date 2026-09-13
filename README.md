<p align="center">
  <img src="docs/media/expand.en.gif" width="680" alt="The notch island unfolds the moment Claude writes how it read the request">
</p>

<h1 align="center">Wishing-Willow</h1>

<p align="center">
  <b>Shows what Claude thinks you asked, next to what you actually said.</b><br>
  A Claude Code plugin, and a notch island for macOS that puts the two side by side while the turn is still running.
</p>

<p align="center">English · <a href="README.zh-CN.md">简体中文</a></p>

```
你批准的  找这类问题的通用逻辑，要可复用的方案
我读成了  ⚠ 审计那个仓库的检查表与 spec，找漂移证据
```

It does not score the two. It does not block anything. Nothing leaves your machine.
Whether they agree is yours to judge — that is the whole design.

<table>
  <tr>
    <td width="50%"><img src="docs/media/expanded.en.png" alt="Expanded island: your request, Claude's reading, the steps it took and a segmented progress bar"></td>
    <td width="50%"><img src="docs/media/waiting.en.png" alt="Expanded island while Claude waits for you to pick an option"></td>
  </tr>
  <tr>
    <td><b>Asked for a diagnosis, read as a rewrite.</b> The request said <i>don’t change any code</i>; the reading says <i>rewrite the retry logic</i>. Nothing flags it — you see both lines and decide.</td>
    <td><b>Claude stopped to ask you something.</b> The island shows the question and the options and sends you back to Claude Code. It never answers for you.</td>
  </tr>
</table>

<sub>Every session in these images is made up. They were recorded on a plain backdrop by <a href="macos/scripts/readme-media.sh"><code>macos/scripts/readme-media.sh</code></a>, driving the real plugin hook and the real app.</sub>

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
/plugin marketplace add yha9806/wishing-willow
/plugin install willow@wishing-willow
```

**2 — the status line** (a plugin cannot ship a `statusLine`; this step is unavoidable)

```
/willow:setup
```

It prints a snippet for your `~/.claude/settings.json`. **It does not edit your
settings for you.** The snippet resolves the installed path at runtime, so a
plugin update does not blank your status line.

**3 — the notch island** (optional, macOS)

```bash
cd macos
make install        # builds with SwiftPM and copies to /Applications
open /Applications/WishingWillow.app
```

Built locally, so there is nothing to sign or notarise: a binary you compiled
yourself carries no quarantine attribute. Details in [`macos/`](macos/).

## Requirements

- Claude Code
- **Node.js** on `PATH` — the hooks are `.mjs` files invoked as `node …`.
  Claude Code ships as a self-contained binary, so having Claude Code is *not*
  evidence you have Node. Check with `node --version`.
- For the island: macOS 26 or later and a Swift 6.2 toolchain (Xcode 26 or its
  command-line tools). Screens without a notch get a virtual one of the same width.
- Tested on macOS. **Windows is untested** — the hook config uses exec form, which
  should be portable, but nobody has run it there.

If Node is missing, the hooks fail as non-blocking errors: Willow won't work, but
nothing else breaks.

## The notch island

The status line shows the two rows after a turn. The island shows them **while the
turn is running** — it tails the transcript itself, so the reading appears the
moment Claude writes it rather than when the turn ends.

<p align="center">
  <img src="docs/media/compact-running.en.png" width="600" alt="Collapsed island: status icon and clock on the left wing, the turn's tag on the right, a second session as a detached pill">
  <br>
  <img src="docs/media/compact-waiting.en.png" width="600" alt="Collapsed island while Claude waits for an answer">
</p>

**Collapsed**, the island is two wings around the camera. The right wing carries
the short tag Claude gave the turn. The left wing carries one combined status icon
and a clock. A second session that has something to say detaches into a small
pill beside it, the way the Dynamic Island handles two live activities.

**Expanded** — on hover, or by itself when a reading arrives or Claude asks you
something — it shows three blocks: *Your request* (verbatim, written by the hook,
out of the model's reach), *Claude's reading*, and *Claude is working*: every tool
call as a plain-language step, and a progress bar.

| Progress bar | Means |
|---|---|
| <img src="docs/media/swatch-before.png" width="14" height="10" alt="purple"> purple | time before Claude wrote its reading |
| <img src="docs/media/swatch-after.png" width="14" height="10" alt="mint"> mint | time after it wrote the reading |
| <img src="docs/media/swatch-waiting.png" width="14" height="10" alt="blue"> blue | time spent waiting on you |
| white knob | the moment the reading was written |
| hairline gaps | one per tool call |

Underneath: context used against the window, cache hits, output tokens this turn,
and how many turns in this session came with a reading.

### Click for the panel

<p align="center">
  <img src="docs/media/open-detail.en.gif" width="700" alt="Click the island: it grows into a panel of sessions and recent turns">
</p>

Click the island and it grows into a panel. On top, every open session;
below, the recent turns of the one you pick — what you asked, how Claude read it,
the tag, how long the turn took. Turns where Claude flagged its own reading with ⚠,
turns where it was asked and wrote nothing, and turns the plugin never asked about
are kept apart rather than folded into one colour, and a chart lays out how long
each turn ran. Click anywhere outside to close it.

<p align="center">
  <img src="docs/media/detail.en.png" width="700" alt="The panel: sessions, recent turns with their readings, and a chart of turn durations">
</p>

### The left wing, element by element

<p align="center">
  <img src="docs/media/left-wing-anatomy.en.png" alt="Annotated left wing: arc lit part is context left, dim part is context used, centre symbol is the turn's state, bottom four dots count running sessions, clock">
</p>

Modelled on the combined status icon of a phone status bar: three shapes, three
facts. The arc is context left (orange at 20%, red at 10%); the centre symbol is
the turn's state; the four dots count the Claude Code sessions running right now.
The drawing is rendered from the real component (`WishingWillow --anatomy <dir>`),
so it cannot drift from what is on screen.

### Language

The island follows the first language in System Settings — Chinese if it starts
with `zh`, English otherwise. `WILLOW_LANG=en` or `WILLOW_LANG=zh` overrides it.
The declaration parser accepts both languages regardless.

## How it works

```mermaid
flowchart LR
  you(["You press Return"]) --> capture["capture.mjs · UserPromptSubmit"]
  capture -- "your prompt, verbatim" --> state[("~/.claude/willow/session.json")]
  capture -- "reminder: say how you read it" --> claude["Claude"]
  claude -- "writes the turn" --> transcript[("transcript .jsonl")]
  transcript --> extract["extract.mjs · Stop"]
  extract -- "reading + tag" --> state
  state --> statusline["statusLine · two rows"]
  state --> island["Notch island · read-only"]
  transcript -. "tailed live" .-> island
```

| | |
|---|---|
| `UserPromptSubmit` | Writes your prompt **verbatim** to `~/.claude/willow/<session>.json`. For substantial requests, asks the model to declare how it read you. Short replies, slash commands and acknowledgements are skipped. |
| `Stop` | Reads the transcript of the turn that just ended and looks for the declaration at the top of the model's messages. Found → records it, along with the short tag. Not found → leaves it `null`. Also prunes state files whose process is gone and that nobody has touched for a week. |
| `statusLine` | Prints the two rows. |
| Notch island | Reads the same state files and tails the live transcript. Never writes to `~/.claude/willow/` — even which turns you have seen is kept in Application Support. |

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

**It cannot check a message you send while Claude is still working.** Claude Code
hands such a message over in the middle of the turn, and on the author's machine the
transcript keeps only the text before a turn's first tool call and its final text — so
a reading Claude writes after that message never reaches the file. Those turns show a
grey *can't verify*, not the orange *no reading*.

**It has not shown that it saves turns.** That is the claim worth testing, and the
turn log below exists to test it. Until that number exists, the honest description
is: it makes the gap visible sooner.

## The turn log

Alongside the state file, each session gets `<session>.log.jsonl` — the last
twenty turns, one line each: what you said, how the model read it, the tag,
whether the plugin asked at all, and when the turn started and ended.

It exists for one number. The claim this plugin makes is that seeing the two rows
saves you turns, and the only way to test that is *drift happened at turn N, you
noticed at turn M* — which cannot be computed without history. On the day the
plugin first worked, the evidence for that number had to be mined out of the raw
transcript by hand.

**It is an index, not a source of truth.** Every load-bearing field can be
recomputed from the transcript, the transcript wins if they disagree, and you can
delete the log whenever you like. `promptField` is the one exception — it records
which hook input key carried your prompt, which the transcript does not know — so
it is for diagnosis only and no statistic may rest on it.

**Whether the plugin asked is recorded, because the alternative produces wrong
numbers.** A short acknowledgement gets no reminder and therefore no declaration;
without `reminded`, that is indistinguishable from a turn where the model was
asked and said nothing.

## Privacy

No network calls. No telemetry. No model calls. State stays in
`~/.claude/willow/`: one small JSON per session plus the twenty-turn log, which
means **your prompts are on disk in a second place**. Nothing reads them unless
you install the macOS app, which reads them locally and sends nothing anywhere.
Delete the directory any time; the plugin recreates it on the next turn. Files
whose process is gone and that nobody has touched for a week are pruned
automatically.

Hooks that mishandle input get in the way of real work, so every failure path here
exits 0 silently — malformed input, missing fields, unwritable directory. The
capture hook blocks your Enter key until it returns, so it does one cheap thing
and gets out of the way.

## Tests

```bash
node tests/replay/run.mjs      # behaviour
node tests/contract/run.mjs    # registration
node tests/runtime/run.mjs     # field names
cd macos && swift test         # the island: parsing, focus rules, timeline, status icon, language
```

Three gates for the plugin, because it has now failed twice in ways a single gate
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

The island's Swift parser is pinned to the plugin's with the same replay cases,
so the two cannot disagree about what counts as a declaration.

## Regenerating the images

```bash
cd macos && swift build -c release
.build/release/WishingWillow --anatomy ../docs/media   # the annotated left wing, both languages
scripts/readme-media.sh                                # stills and GIFs, both languages
```

The media script needs screen-recording permission and an unlocked screen. It
first lays a plain backdrop over the area below the notch that it records, so
nothing else on your desktop ends up in a picture.

## License

MIT
