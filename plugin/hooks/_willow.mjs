// Shared helpers for the two hooks.
//
// Design rule that governs this whole file: a hook that throws is a hook that
// gets in the way. UserPromptSubmit blocks the user's Enter key until it
// returns, so every path here either succeeds quickly or gives up silently.
// Nothing in this plugin is important enough to interrupt someone's work.

import { readFileSync, writeFileSync, renameSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

export const SCHEMA = 2;

/** Where state lives. Overridable so tests never touch the real directory. */
export function stateDir() {
  return process.env.WILLOW_STATE_DIR || join(homedir(), '.claude', 'willow');
}

/** Read all of stdin. Returns '' if anything goes wrong. */
export function readStdin() {
  try {
    return readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

/** Parse hook input. Returns null rather than throwing on malformed JSON. */
export function parseInput(raw) {
  if (!raw || !raw.trim()) return null;
  try {
    const v = JSON.parse(raw);
    return v && typeof v === 'object' ? v : null;
  } catch {
    return null;
  }
}

/**
 * Pull the user's prompt out of the hook input, and say which key it came from.
 *
 * The field name is `prompt` — verified against the shipped Claude Code binary
 * (2.1.252), not against the docs, which say `user_prompt`. Writing the code
 * from the docs is how this plugin spent its first day capturing nothing at
 * all: the hook ran, found no `user_prompt`, and exited 0 in silence.
 *
 * Both names are accepted so that whichever one a given build sends, the
 * prompt still lands. Returning the key alongside the text lets the reader
 * tell "the model declared nothing" apart from "we could not read the input" —
 * two states that otherwise look identical, which is the failure this whole
 * plugin exists to break.
 */
export function readPrompt(input) {
  for (const field of ['prompt', 'user_prompt']) {
    const v = input?.[field];
    if (typeof v === 'string') return { text: v, field };
  }
  return { text: null, field: null };
}

/** A session id safe to use as a filename. */
function safeId(id) {
  return typeof id === 'string' && /^[A-Za-z0-9._-]{1,128}$/.test(id) ? id : null;
}

export function statePath(sessionId) {
  const id = safeId(sessionId);
  return id ? join(stateDir(), `${id}.json`) : null;
}

export function readState(sessionId) {
  const p = statePath(sessionId);
  if (!p || !existsSync(p)) return null;
  try {
    return JSON.parse(readFileSync(p, 'utf8'));
  } catch {
    return null;
  }
}

/**
 * Write state atomically: temp file, then rename(2).
 *
 * The temp name deliberately does not end in `.json` — readers glob for
 * `*.json`, so an in-flight write can never be picked up half-written.
 */
export function writeState(sessionId, record) {
  const p = statePath(sessionId);
  if (!p) return false;
  try {
    mkdirSync(stateDir(), { recursive: true });
    const tmp = `${p}.${process.pid}.tmp`;
    writeFileSync(tmp, JSON.stringify(record, null, 2), 'utf8');
    renameSync(tmp, p);
    return true;
  } catch {
    return false;
  }
}

/**
 * Requests that should not be interrupted with a reminder.
 *
 * Calibrated against real turns from the conversation this plugin came out of:
 * "好的 继续吧 没问题" (9 chars) must pass through untouched, while
 * "可以继续吧 问题就是我需要你找到最优解 基于..." (40 chars) must not.
 */
const ACK_ONLY = /^(?:[好可行]的?|可以|没问题|继续(?:吧)?|开始(?:吧)?|走吧|对|是的|嗯+|谢谢|多谢|辛苦了?|ok|okay|k|yes|yep|sure|thanks|thx|go|go ahead|continue|proceed|next|done|lgtm|\s|[，。、！？~…,.!?])+$/iu;

/**
 * Rough information weight, not character count.
 *
 * Calibrated on real turns: "这是什么意思 给我解释一下" is 13 characters but a
 * complete request, while "explain this to me please" is 25 characters and the
 * same request. Counting characters bypasses the Chinese one and catches the
 * English one, which is backwards. A CJK character carries roughly 2.5x what a
 * Latin one does, so weigh accordingly.
 */
function weigh(s) {
  let w = 0;
  for (const ch of s) {
    const c = ch.codePointAt(0);
    const cjk =
      (c >= 0x3400 && c <= 0x9fff) ||   // CJK unified ideographs (+ ext A)
      (c >= 0xf900 && c <= 0xfaff) ||   // compatibility ideographs
      (c >= 0x3040 && c <= 0x30ff) ||   // kana
      (c >= 0xac00 && c <= 0xd7af) ||   // hangul syllables
      (c >= 0x20000 && c <= 0x3ffff);   // CJK ext B+
    if (cjk) w += 2.5;
    else if (/\s/.test(ch)) w += 0.5;
    else w += 1;
  }
  return w;
}

// Deliberately low, with ACK_ONLY carrying the acknowledgements. The costs are
// asymmetric: an unnecessary reminder costs a few dozen tokens, a missed one
// costs a whole turn of work in the wrong direction. Err toward reminding.
const MIN_WEIGHT = 20;

export function shouldBypass(prompt) {
  if (typeof prompt !== 'string') return true;
  const t = prompt.trim();
  if (t.length === 0) return true;
  if (t.startsWith('/')) return true;              // slash command
  if (ACK_ONLY.test(t)) return true;               // purely an acknowledgement
  if (weigh(t) < MIN_WEIGHT) return true;          // too slight to misread meaningfully
  return false;
}

/** Exit without disturbing anything. Never exit 2 — that erases the user's prompt. */
export function quietExit() {
  process.exit(0);
}
