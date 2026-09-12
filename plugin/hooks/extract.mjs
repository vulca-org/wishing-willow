#!/usr/bin/env node
// Stop — pull the model's decode line out of the turn it just finished.
//
// If the line isn't there, we leave `decode` null and say nothing. A missing
// declaration is not an error to be corrected here; it is the state the reader
// is supposed to show you.

import { openSync, readSync, closeSync, statSync } from 'node:fs';
import {
  SCHEMA, readStdin, parseInput, readState, writeState, appendTurnLog, pruneState, quietExit,
} from './_willow.mjs';

// Chinese full-width and ASCII colons both, plus an English form so the plugin
// is usable outside Chinese sessions.
const DECODE_LINE = /^\s*(?:我读成了|我理解为|How I read it|Read as)\s*[：:]\s*(.+?)\s*$/iu;
const TAG_LINE = /^\s*(?:标签|Tag)\s*[：:]\s*(.+?)\s*$/iu;

const SCAN_LINES = 12;   // the declaration belongs at the top of a message or not at all

/**
 * Find the declaration near the start of one message.
 *
 * Lines inside a code fence, a blockquote, or an indented block are skipped:
 * **quoting a declaration is not making one.** On 2026-09-12 the model pasted
 * another session's two lines into a fenced block to demonstrate them, and this
 * function recorded the quotation as that turn's declaration — the same bug then
 * corrupted a measurement later the same day (31 declarations counted where
 * there were 9). Returns null unless a decode line is found; a lone tag means
 * nothing on its own.
 */
function scanMessage(message) {
  if (typeof message !== 'string' || !message) return null;
  let seen = 0;
  let fence = null;
  let decode = null;
  let tag = null;

  for (const line of message.split(/\r?\n/)) {
    const t = line.trim();

    const f = /^(`{3,}|~{3,})/.exec(t);
    if (f) {
      const kind = f[1][0];
      if (fence === kind) fence = null;
      else if (fence === null) fence = kind;
      continue;
    }
    if (fence !== null) continue;              // 栅栏内 = 引用
    if (t === '') continue;
    if (t.startsWith('>')) continue;           // 引用块
    if (/^\s{4,}\S/.test(line)) continue;      // 缩进代码

    if (++seen > SCAN_LINES) break;

    if (decode === null) {
      const m = DECODE_LINE.exec(line);
      if (m) decode = m[1].trim() || null;     // ⚠ 若在，原样留着：那是模型自己的判断
    }
    if (tag === null) {
      const m = TAG_LINE.exec(line);
      if (m) tag = m[1].trim() || null;
    }
    if (decode !== null && tag !== null) break;
  }

  return decode === null ? null : { decode, tag };
}

/** Read from `from` to EOF, at most `max` bytes. Returns '' on any failure. */
function slice(path, from, max) {
  let fd;
  try {
    const size = statSync(path).size;
    if (!(from >= 0) || from > size) return '';
    const len = Math.min(size - from, max);
    if (len <= 0) return '';
    fd = openSync(path, 'r');
    const buf = Buffer.alloc(len);
    readSync(fd, buf, 0, len, from);
    return buf.toString('utf8');
  } catch {
    return '';
  } finally {
    if (fd !== undefined) { try { closeSync(fd); } catch { /* nothing to do */ } }
  }
}

/** Scan a chunk of transcript rows in order; returns the first declaration found. */
function scanRows(text) {
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    let row;
    try { row = JSON.parse(line); } catch { continue; }   // 截断的半行
    for (const t of assistantTexts(row)) {
      const hit = scanMessage(t);
      if (hit) return hit;
    }
  }
  return null;
}

/** Read at most `max` bytes from the end of a file. Returns '' on any failure. */
function tail(path, max) {
  let fd;
  try {
    const size = statSync(path).size;
    const len = Math.min(size, max);
    fd = openSync(path, 'r');
    const buf = Buffer.alloc(len);
    readSync(fd, buf, 0, len, size - len);
    const text = buf.toString('utf8');
    // A window that starts mid-file almost certainly starts mid-line.
    return len < size ? text.slice(text.indexOf('\n') + 1) : text;
  } catch {
    return '';
  } finally {
    if (fd !== undefined) { try { closeSync(fd); } catch { /* nothing to do */ } }
  }
}

/** A transcript row that is the human speaking — not a tool result, not a sidechain. */
function isUserTurn(row) {
  if (row?.type !== 'user' || row.isSidechain === true || row.isMeta === true) return false;
  const c = row.message?.content;
  if (typeof c === 'string') return true;
  if (!Array.isArray(c)) return false;
  return c.some((b) => b?.type === 'text') && !c.some((b) => b?.type === 'tool_result');
}

/** Assistant text blocks, in order. */
function assistantTexts(row) {
  if (row?.type !== 'assistant' || row.isSidechain === true) return [];
  const c = row.message?.content;
  if (typeof c === 'string') return [c];
  if (!Array.isArray(c)) return [];
  return c.filter((b) => b?.type === 'text' && typeof b.text === 'string').map((b) => b.text);
}

/**
 * Find the decode line in the turn that just ended.
 *
 * `last_assistant_message` is not the reply — it is the *last* message of the
 * turn. A turn that calls tools ends with whatever prose came after the final
 * tool result, fifteen messages downstream of where the declaration belongs.
 * The first real turn this plugin ever saw did exactly that: the model declared
 * correctly in message #1 and `last_assistant_message` was message #15, so the
 * declaration was recorded as absent. Read the transcript instead, and treat
 * `last_assistant_message` as the fallback for when it cannot be read.
 */
function findDeclaration(input, prev) {
  const path = input?.transcript_path;

  // 首选：capture 在提交那一刻记下的偏移。从那里往后读就是这一轮，
  // 没有边界搜索，也没有「窗口不够大」这种失败模式。
  if (typeof path === 'string' && path && typeof prev?.transcriptOffset === 'number') {
    const text = slice(path, prev.transcriptOffset, 64 << 20);
    if (text) {
      const hit = scanRows(text);
      if (hit) return hit;
      // 偏移有效但这一轮里没有声明 —— 这是确定的答案，不必再回溯。
      if (prev.transcriptOffset <= (() => { try { return statSync(path).size; } catch { return -1; } })()) {
        return null;
      }
    }
  }

  if (typeof path === 'string' && path) {
    // Two bounded passes: a turn with large tool output can be several MB.
    // WILLOW_TAIL_MAX exists so a test can shrink the window and actually
    // exercise the "boundary is out of reach" path instead of asserting against
    // a window big enough to hide it.
    const cap = Number(process.env.WILLOW_TAIL_MAX) || 0;
    const windows = cap > 0 ? [cap] : [2 << 20, 16 << 20];
    for (const window of windows) {
      const text = tail(path, window);
      if (!text) break;

      const rows = [];
      for (const line of text.split('\n')) {
        if (!line.trim()) continue;
        try { rows.push(JSON.parse(line)); } catch { /* truncated or not a row */ }
      }

      let start = -1;
      for (let i = rows.length - 1; i >= 0; i -= 1) {
        if (isUserTurn(rows[i])) { start = i; break; }
      }
      // Boundary not in this window: a wider one may contain it. Never scan
      // without a boundary — a hit from an earlier turn would be reported as
      // this turn's declaration, which is worse than reporting none.
      if (start === -1) continue;

      for (const row of rows.slice(start + 1)) {
        for (const t of assistantTexts(row)) {
          const hit = scanMessage(t);
          if (hit) return hit;
        }
      }
      return null;   // boundary found, turn scanned, nothing declared
    }
  }
  return scanMessage(input?.last_assistant_message);
}

try {
  const input = parseInput(readStdin());
  if (!input) quietExit();

  const sessionId = input.session_id;
  if (typeof sessionId !== 'string') quietExit();

  const prev = readState(sessionId);
  const found = findDeclaration(input, prev);
  const decode = found?.decode ?? null;
  const tag = found?.tag ?? null;

  // Only ever touch `decode` and the timestamp. `prompt` stays exactly as
  // capture.mjs wrote it — this hook has no business rewriting what you said.
  const endedAt = new Date().toISOString();

  if (prev) {
    writeState(sessionId, { ...prev, decode, tag, updatedAt: endedAt });
    // 只在 capture 跑过的时候记日志：没有 capture 就没有原话，也没有「问没问」，
    // 记一条三个字段都是 null 的东西只会让统计更难看懂。
    appendTurnLog(sessionId, {
      turnId: prev.turnId ?? null,
      at: prev.updatedAt ?? null,
      endedAt,
      reminded: prev.reminded ?? null,
      promptField: prev.promptField ?? null,
      origin: prev.origin ?? null,
      prompt: prev.prompt ?? null,
      decode,
      tag,
    });
  } else {
    // Stop without a preceding capture (plugin installed mid-turn, state wiped).
    // Record what we can rather than inventing a prompt.
    writeState(sessionId, {
      schema: SCHEMA,
      sessionId,
      pid: process.ppid,
      cwd: typeof input.cwd === 'string' ? input.cwd : null,
      turnId: typeof input.prompt_id === 'string' ? input.prompt_id : null,
      // 轮次只有 capture 知道，而这条路径正是「没有 capture」。
      // 写 0 是编一个看起来确定的数；不知道就写 null，读方显示「—」。
      turnIndex: null,
      updatedAt: new Date().toISOString(),
      prompt: null,
      decode,
      tag,
      endedAt: null,
    });
  }
  pruneState(sessionId);
  process.exit(0);
} catch {
  quietExit();
}
