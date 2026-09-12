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
  '【Wishing-Willow】请在本轮回复的最开头写三行，然后再回答：\n' +
  '你批准的：<一句话写出用户要的>\n' +
  '我读成了：<一句话写出你把这个请求读成了什么任务；与上一行不一致时，本行开头标 ⚠>\n' +
  '标签：<把上一行压成 ≤6 个汉字（英文 ≤14 字符），动词+宾语；' +
  '禁止「继续 / 往下做 / 处理 / 优化 / 完善 / 推进 / 跟进」这类不含信息的词>\n' +
  '三行一致时也照写，保持平淡。不要解释这三行本身。';

// 标签那一行是给菜单栏／刘海那条常亮层用的：刘海 156pt，11pt 中文大约 14 个字，
// 一句解码放不下。它必须由模型自己压，**不能由读方截断解码行** —— 实测
// 「起草不发送，发送等你一句话」截到 14 个字是「起草那封跟进信，内容具体到…」，
// 「不发送」被切掉，意思正好反过来。截断名字是安全的，截断解码是危险的。

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
    tag: null,             // ≤6 字，同样由 extract.mjs 填
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
