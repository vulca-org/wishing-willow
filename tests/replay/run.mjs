#!/usr/bin/env node
// Replay runner — 第一关。
//
// 它测的是 hook 的确定性行为，不是模型的行为：
// 给定一段没有声明的回复，extract 是否正确留下 decode=null；
// 给定有声明的，是否正确提取。
//
// 纪律（用户全局规则〈八〉〈九〉）：这个 runner 必须先在空实现上跑出全红，
// 才允许去写实现。没验证过能变红的测试是摆设。

import { readFileSync, existsSync, mkdtempSync, rmSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, '..', '..');
const HOOKS = join(REPO, 'plugin', 'hooks');
const CASES = join(HERE, 'cases');

const read = (p) => JSON.parse(readFileSync(p, 'utf8'));

/** 跑一个 hook，返回 {code, stdout, stderr}。stdin 以原始字节喂入（畸形输入也要能喂）。 */
function runHook(script, stdinPath, stateDir) {
  const entry = join(HOOKS, script);
  if (!existsSync(entry)) {
    return { code: null, stdout: '', stderr: `MISSING: ${entry}`, missing: true };
  }
  const r = spawnSync('node', [entry], {
    input: readFileSync(stdinPath),
    env: { ...process.env, WILLOW_STATE_DIR: stateDir },
    encoding: 'utf8',
    timeout: 10_000,
  });
  return { code: r.status, stdout: r.stdout ?? '', stderr: r.stderr ?? '' };
}

/** 状态目录里唯一的那个 .json（hook 以 session id 命名）。 */
function readState(stateDir) {
  if (!existsSync(stateDir)) return null;
  const files = readdirSync(stateDir).filter((f) => f.endsWith('.json'));
  if (files.length === 0) return null;
  return read(join(stateDir, files[0]));
}

const failures = [];
function check(caseName, label, ok, detail) {
  if (!ok) failures.push(`${caseName} · ${label}${detail ? ` — ${detail}` : ''}`);
  return ok;
}

const caseNames = readdirSync(CASES).filter((d) => !d.startsWith('.')).sort();
console.log(`\n  replay · ${caseNames.length} cases\n`);

for (const name of caseNames) {
  const dir = join(CASES, name);
  const expect = read(join(dir, 'expect.json'));
  const stateDir = mkdtempSync(join(tmpdir(), 'willow-test-'));
  const marks = [];

  try {
    // ── capture (UserPromptSubmit) ────────────────────────────────────────
    const ups = join(dir, 'user-prompt-submit.json');
    if (existsSync(ups) && expect.capture) {
      const r = runHook('capture.mjs', ups, stateDir);
      if (r.missing) {
        check(name, 'capture', false, r.stderr);
        marks.push('capture:MISSING');
      } else {
        const codeOk = check(name, 'capture.exit_code', r.code === expect.capture.exit_code,
          `期望 ${expect.capture.exit_code}，得到 ${r.code}${r.stderr ? ` (stderr: ${r.stderr.trim().slice(0, 80)})` : ''}`);

        const out = r.stdout.trim();
        const injected = out.length > 0;
        const wantInject = expect.capture.stdout === 'inject';
        const injOk = check(name, 'capture.stdout', injected === wantInject,
          wantInject ? '期望注入，但输出为空' : `期望不注入，却输出了 ${out.length} 字符`);

        // 注入时必须是合法 JSON，且必须以 { 开头并以 } 结尾
        // —— 官方规则：以 { 开头但不以 } 结尾会被当纯文本
        let shapeOk = true;
        if (injected) {
          shapeOk = check(name, 'capture.stdout.shape',
            out.startsWith('{') && out.endsWith('}') && (() => { try { JSON.parse(out); return true; } catch { return false; } })(),
            '注入的 stdout 必须是完整合法 JSON');
        }
        marks.push(`capture:${codeOk && injOk && shapeOk ? 'ok' : 'FAIL'}`);
      }
    }

    // ── extract (Stop) ───────────────────────────────────────────────────
    const stop = join(dir, 'stop.json');
    if (existsSync(stop) && expect.extract) {
      const r = runHook('extract.mjs', stop, stateDir);
      if (r.missing) {
        check(name, 'extract', false, r.stderr);
        marks.push('extract:MISSING');
      } else {
        const ok = check(name, 'extract.exit_code', r.code === expect.extract.exit_code,
          `期望 ${expect.extract.exit_code}，得到 ${r.code}`);
        marks.push(`extract:${ok ? 'ok' : 'FAIL'}`);
      }
    }

    // ── 状态文件 ──────────────────────────────────────────────────────────
    const state = readState(stateDir);
    if (expect.state_file === null) {
      check(name, 'state_file', state === null, '期望不写状态文件，却写了');
      marks.push(`state:${state === null ? 'ok' : 'FAIL'}`);
    } else if (expect.state_file) {
      let ok = check(name, 'state_file', state !== null, '期望有状态文件，却没有');
      if (state) {
        if ('decode' in expect.state_file) {
          const want = expect.state_file.decode;
          const got = state.decode ?? null;
          ok = check(name, 'state.decode', got === want,
            `期望 ${JSON.stringify(want)}，得到 ${JSON.stringify(got)}`) && ok;
        }
        if ('prompt' in expect.state_file) {
          const want = expect.state_file.prompt;
          const got = state.prompt ?? null;
          ok = check(name, 'state.prompt', got === want,
            `期望 ${JSON.stringify(want)}，得到 ${JSON.stringify(got)}`) && ok;
        }
        if ('promptField' in expect.state_file) {
          const want = expect.state_file.promptField;
          const got = state.promptField ?? null;
          ok = check(name, 'state.promptField', got === want,
            `期望 ${JSON.stringify(want)}，得到 ${JSON.stringify(got)}`) && ok;
        }
        if (expect.state_file.prompt_startswith) {
          const p = state.prompt ?? '';
          ok = check(name, 'state.prompt', p.startsWith(expect.state_file.prompt_startswith),
            `prompt 应以「${expect.state_file.prompt_startswith}」开头，得到「${p.slice(0, 30)}…」`) && ok;
        }
        // prompt 必须逐字保存 —— A1 的核心，绝不允许被改写。
        // 原话从 fixture 实际用的那个键里取，不写死键名：写死键名正是
        // 2026-09-12 那个 bug 能躲过整套测试的原因。
        const rawPrompt = existsSync(ups) ? (() => {
          try {
            const raw = read(ups);
            for (const f of ['prompt', 'user_prompt']) {
              if (typeof raw[f] === 'string') return raw[f];
            }
          } catch { /* 畸形输入交给别的断言 */ }
          return null;
        })() : null;
        if (rawPrompt != null) {
          ok = check(name, 'state.prompt.verbatim', state.prompt === rawPrompt,
            'prompt 必须与输入的原话逐字一致') && ok;
        }
      }
      marks.push(`state:${ok ? 'ok' : 'FAIL'}`);
    }
  } finally {
    rmSync(stateDir, { recursive: true, force: true });
  }

  const bad = marks.some((m) => m.includes('FAIL') || m.includes('MISSING'));
  console.log(`  ${bad ? '✗' : '✓'} ${name.padEnd(24)} ${marks.join('  ')}`);
}

console.log('');
if (failures.length) {
  console.log(`  ${failures.length} 项失败：\n`);
  for (const f of failures) console.log(`    · ${f}`);
  console.log('');
  process.exit(1);
}
console.log('  全部通过\n');
