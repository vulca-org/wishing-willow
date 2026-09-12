#!/usr/bin/env node
// statusLine — two rows: what you said, and how the model read it.
//
// Claude Code blanks the status line if this exits non-zero or prints nothing,
// so every failure path still prints something harmless.

import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const DIM = '\x1b[2m';
const WARN = '\x1b[33m';
const RESET = '\x1b[0m';

/** Display width: CJK and fullwidth punctuation occupy two columns. */
function width(s) {
  let w = 0;
  for (const ch of s) {
    const c = ch.codePointAt(0);
    w +=
      (c >= 0x1100 && c <= 0x115f) ||
      (c >= 0x2e80 && c <= 0xa4cf) ||
      (c >= 0xac00 && c <= 0xd7a3) ||
      (c >= 0xf900 && c <= 0xfaff) ||
      (c >= 0xfe30 && c <= 0xfe6f) ||
      (c >= 0xff00 && c <= 0xff60) ||
      (c >= 0xffe0 && c <= 0xffe6) ||
      (c >= 0x20000 && c <= 0x3fffd)
        ? 2
        : 1;
  }
  return w;
}

function truncate(s, max) {
  const flat = s.replace(/\s+/g, ' ').trim();
  if (width(flat) <= max) return flat;
  let out = '';
  let w = 0;
  for (const ch of flat) {
    const cw = width(ch);
    if (w + cw > max - 1) break;
    out += ch;
    w += cw;
  }
  return out + '…';
}

function main() {
  let input = {};
  try {
    input = JSON.parse(readFileSync(0, 'utf8')) ?? {};
  } catch {
    /* fall through to the idle line */
  }

  const dir = process.env.WILLOW_STATE_DIR || join(homedir(), '.claude', 'willow');
  const id = input.session_id;
  const path = typeof id === 'string' && /^[A-Za-z0-9._-]{1,128}$/.test(id)
    ? join(dir, `${id}.json`)
    : null;

  if (!path || !existsSync(path)) {
    process.stdout.write(`${DIM}🌿 willow · 待首轮${RESET}`);
    return;
  }

  let state;
  try {
    state = JSON.parse(readFileSync(path, 'utf8'));
  } catch {
    process.stdout.write(`${DIM}🌿 willow · 状态不可读${RESET}`);
    return;
  }

  // The status line lives in a narrow strip; leave room for the label and padding.
  const cols = Number(process.env.COLUMNS) || 100;
  const room = Math.max(20, cols - 14);

  const asked = typeof state.prompt === 'string' && state.prompt.trim()
    ? truncate(state.prompt, room)
    : '—';

  // Absence of `decode` is the signal. Never inferred, never scored — the two
  // rows sit side by side and the reader decides whether they agree.
  const decode = typeof state.decode === 'string' && state.decode.trim()
    ? state.decode.trim()
    : null;

  const line1 = `${DIM}你批准的${RESET} ${asked}`;
  const line2 = decode
    ? `${DIM}我读成了${RESET} ${truncate(decode, room)}`
    : `${WARN}⚠ 本轮未声明${RESET}`;

  process.stdout.write(`${line1}\n${line2}`);
}

try {
  main();
} catch {
  process.stdout.write(`${DIM}🌿 willow${RESET}`);
}
