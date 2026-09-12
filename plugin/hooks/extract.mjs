#!/usr/bin/env node
// Stop — pull the model's decode line out of the reply it just finished.
//
// If the line isn't there, we leave `decode` null and say nothing. A missing
// declaration is not an error to be corrected here; it is the state the reader
// is supposed to show you.

import {
  SCHEMA, readStdin, parseInput, readState, writeState, quietExit,
} from './_willow.mjs';

// Chinese full-width and ASCII colons both, plus an English form so the plugin
// is usable outside Chinese sessions.
const DECODE_LINE = /^\s*(?:我读成了|我理解为|How I read it|Read as)\s*[：:]\s*(.+?)\s*$/iu;

const SCAN_LINES = 12;   // the declaration belongs at the top or not at all

/** Find the decode line near the start of the reply. Returns null if absent. */
function findDecode(message) {
  if (typeof message !== 'string' || !message) return null;
  const lines = message.split(/\r?\n/);
  let seen = 0;
  for (const line of lines) {
    if (line.trim() === '') continue;
    if (++seen > SCAN_LINES) break;
    const m = DECODE_LINE.exec(line);
    if (m) {
      const text = m[1].trim();
      return text.length ? text : null;
    }
  }
  return null;
}

try {
  const input = parseInput(readStdin());
  if (!input) quietExit();

  const sessionId = input.session_id;
  if (typeof sessionId !== 'string') quietExit();

  const decode = findDecode(input.last_assistant_message);
  const prev = readState(sessionId);

  // Only ever touch `decode` and the timestamp. `prompt` stays exactly as
  // capture.mjs wrote it — this hook has no business rewriting what you said.
  if (prev) {
    writeState(sessionId, { ...prev, decode, updatedAt: new Date().toISOString() });
  } else {
    // Stop without a preceding capture (plugin installed mid-turn, state wiped).
    // Record what we can rather than inventing a prompt.
    writeState(sessionId, {
      schema: SCHEMA,
      sessionId,
      pid: process.ppid,
      cwd: typeof input.cwd === 'string' ? input.cwd : null,
      turnId: typeof input.prompt_id === 'string' ? input.prompt_id : null,
      turnIndex: typeof input.turn_index === 'number' ? input.turn_index : 0,
      updatedAt: new Date().toISOString(),
      prompt: null,
      decode,
      endedAt: null,
    });
  }
  process.exit(0);
} catch {
  quietExit();
}
