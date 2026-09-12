#!/usr/bin/env node
// UserPromptSubmit — store the prompt verbatim, and (for substantial requests
// only) remind the model to declare how it read the request.
//
// This hook runs before Claude sees your message and blocks until it returns,
// so it does exactly two cheap things and then gets out of the way.

import {
  SCHEMA, readStdin, parseInput, readPrompt, readState, writeState, shouldBypass, quietExit,
} from './_willow.mjs';

const REMINDER =
  '【Wishing-Willow】请在本轮回复的最开头写两行，然后再回答：\n' +
  '你批准的：<用一句话写出用户要的>\n' +
  '我读成了：<用一句话写出你把这个请求读成了什么任务>\n' +
  '两者一致时也要写，保持平淡；不一致时在第二行开头标 ⚠。不要解释这两行本身。';

try {
  const input = parseInput(readStdin());
  if (!input) quietExit();

  const sessionId = input.session_id;
  if (typeof sessionId !== 'string') quietExit();

  const { text: prompt, field: promptField } = readPrompt(input);

  // The prompt is written exactly as submitted. Nothing in this plugin — and
  // nothing the model can do — rewrites this field. That asymmetry is the point.
  //
  // When no prompt field matched, the record is still written, with both
  // `prompt` and `promptField` null. That combination means "the hook ran and
  // could not read this turn's input" — a broken plugin, not a quiet model —
  // and the reader shows it as such instead of leaving the screen blank.
  const prev = readState(sessionId);
  writeState(sessionId, {
    schema: SCHEMA,
    sessionId,
    pid: process.ppid,
    cwd: typeof input.cwd === 'string' ? input.cwd : null,
    turnId: typeof input.prompt_id === 'string' ? input.prompt_id : null,
    turnIndex: (prev?.turnIndex ?? -1) + 1,
    updatedAt: new Date().toISOString(),
    prompt,
    promptField,
    decode: null,          // absence is the signal; extract.mjs fills it in
    endedAt: null,
  });

  if (prompt === null || shouldBypass(prompt)) quietExit();

  // Must be complete, valid JSON: Claude Code treats output starting with '{'
  // but not ending in '}' as plain text.
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'UserPromptSubmit',
      additionalContext: REMINDER,
    },
  }));
  process.exit(0);
} catch {
  quietExit();
}
