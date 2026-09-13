#!/bin/bash
# README 素材：在 --backdrop 的干净底色上，用虚构的会话按真实事件顺序跑一遍灵动岛，拍中英两套静帧和一段展开动图。
#
#   macos/scripts/readme-media.sh [二进制]      默认 macos/.build/release/WishingWillow
#   PARTS=motion macos/scripts/readme-media.sh  只重录动图（stills / motion，默认两样都录）
#
# 输出到 docs/media/，中间文件在 macos/build/readme-media/（不进仓库）。
# 需要：屏幕录制权限（screencapture）、node、ffmpeg。会先关掉正在跑的 WishingWillow。
# 数据全部虚构（工作区 atlas / billing、上传测试的对话）；拍摄区域先盖一层底色（--backdrop，刘海下方 760×520pt），不会拍进别的窗口。
# 屏幕锁定时区域截图会失败（could not create image from rect），先解锁。
# 事件照真的来：会话由插件自己的 capture.mjs 建，transcript 一行一行追加，灵动岛按到达时刻展开收起。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${1:-$ROOT/macos/.build/release/WishingWillow}"
OUT="$ROOT/docs/media"
WORK="$ROOT/macos/build/readme-media"
HOOKS="$ROOT/plugin/hooks"
mkdir -p "$OUT"
PARTS="${PARTS:-stills motion}"
mkdir -p "$WORK"

# 刘海在屏幕水平正中；截图区域都以它为轴。
W=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var s = $.NSScreen.screens; var f = s.objectAtIndex(0).frame; f.size.width')
C=$(python3 -c "print(int(float('$W') / 2))")
EXPANDED="$((C - 340)),0,680,500"
COMPACT="$((C - 300)),0,600,96"

log() { echo "$(date +%H:%M:%S) $*"; }
now() { python3 -c 'import datetime;print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3]+"Z")'; }
stop() { pkill -x WishingWillow 2>/dev/null || true; pkill -f "WishingWillow.release" 2>/dev/null || true; sleep 0.8; }
shot() { rm -f "$2"; screencapture -x -R "$1" "$2"; log "静帧 $(basename "$2")"; }

row() {  # $1 transcript  $2 事件  $3 语言
  python3 - "$1" "$2" "$3" "$(now)" <<'ROWS'
import json, sys
path, kind, lang, ts = sys.argv[1:5]
zh = lang == "zh"
def A(mid, content, read, write=2400, out=900):
    return {"type": "assistant", "isSidechain": False, "timestamp": ts,
            "message": {"id": mid, "role": "assistant", "model": "claude-opus-5",
                        "usage": {"input_tokens": 3, "cache_creation_input_tokens": write,
                                  "cache_read_input_tokens": read, "output_tokens": out},
                        "content": content}}
def tool(mid, tid, name, inp, read, out=600):
    return A(mid, [{"type": "tool_use", "id": tid, "name": name, "input": inp}], read, out=out)
declare = ("你批准的：只找出上传测试为什么只在 CI 上失败，不改代码。\n"
           "我读成了：重写上传测试的重试逻辑，把不稳定的测试修好。\n"
           "标签：修上传测试") if zh else (
           "You approved: find out why the upload test fails only on CI, without changing code.\n"
           "How I read it: Rewrite the upload test’s retry logic so it stops flaking.\n"
           "Tag: Rewrite retry")
rows = {
 "thinking": [A("m1", [{"type": "thinking", "thinking": ""}], 412000)],
 "declare": [A("m1", [{"type": "text", "text": declare}], 412000)],
 "grep": [tool("m2", "t1", "Grep", {"pattern": "retry"}, 418000, 400)],
 "bash": [tool("m3", "t2", "Bash", {"command": "go test ./upload/...", "description": "运行上传测试" if zh else "Run upload tests"}, 425000, 700)],
 "read": [tool("m4", "t3", "Read", {"file_path": "/work/atlas/upload/upload_test.go"}, 431000, 500)],
 "edit": [tool("m5", "t4", "Edit", {"file_path": "/work/atlas/upload/retry.go"}, 440000, 1600)],
 "ask": [tool("m6", "toolu_media_q", "AskUserQuestion", {"questions": [{
     "question": "重试策略用哪种？" if zh else "Which retry policy should I use?",
     "header": "重试" if zh else "Retry", "multiSelect": False,
     "options": [{"label": "指数退避" if zh else "Exponential backoff", "description": ""},
                 {"label": "固定重试 3 次" if zh else "Fixed, 3 attempts", "description": ""}]}]}, 452000, 500)],
 "other": [A("o1", [{"type": "thinking", "thinking": ""}], 96000, out=300)],
}[kind]
with open(path, "a") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
ROWS
}

session() {  # $1 状态目录  $2 会话 id  $3 工作区  $4 原话
  local T="$1/$2.transcript.jsonl"
  mkdir -p "$1"
  echo '{"type":"assistant","isSidechain":false,"timestamp":"2026-09-13T08:00:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"—"}]}}' > "$T"
  python3 -c 'import json,sys;print(json.dumps({"session_id":sys.argv[1],"hook_event_name":"UserPromptSubmit","cwd":sys.argv[2],"prompt_id":"p-"+sys.argv[1],"transcript_path":sys.argv[3],"prompt":sys.argv[4]},ensure_ascii=False),end="")' \
    "$2" "$3" "$T" "$4" | WILLOW_STATE_DIR="$1" node "$HOOKS/capture.mjs" >/dev/null
  # 演示进程早就退出了，pid 记成 1（launchd，永远在）以免被当成已关闭的会话。
  python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["pid"]=1;json.dump(d,open(p,"w"),ensure_ascii=False)' "$1/$2.json"
}

prompts() {  # $1 语言 → 两句原话（主会话、另一个会话）
  if [ "$1" = zh ]; then
    MAIN_PROMPT="上传测试为什么只在 CI 上挂？先找原因，别改代码。"
    OTHER_PROMPT="把账单导出改成按月分文件。"
  else
    MAIN_PROMPT="Why does the upload test fail only on CI? Find the cause first — don’t change any code."
    OTHER_PROMPT="Split the billing export into one file per month."
  fi
}

# ---- 静帧：收起（在跑 + 胶囊）→ 声明到达展开 → 等你选择展开 → 收起（问号计时） ----
for L in en zh; do
  case " $PARTS " in *" stills "*) ;; *) break ;; esac
  prompts "$L"
  D="$WORK/stills-$L"
  rm -rf "$D"
  session "$D" "media-main-$L" /work/atlas "$MAIN_PROMPT"
  session "$D" "media-other-$L" /work/billing "$OTHER_PROMPT"
  TM="$D/media-main-$L.transcript.jsonl"; TO="$D/media-other-$L.transcript.jsonl"
  stop
  WILLOW_LANG=$L WILLOW_STATE_DIR="$D" "$BIN" --present 36 --real --passive --backdrop 2>"$WORK/stills-$L.log" &
  sleep 3
  row "$TO" other "$L"; row "$TM" thinking "$L"; sleep 4
  shot "$COMPACT" "$OUT/compact-running.$L.png"
  row "$TM" declare "$L"; sleep 0.8
  row "$TM" grep "$L";    sleep 0.7
  row "$TM" bash "$L";    sleep 0.8
  row "$TM" read "$L";    sleep 1.2
  shot "$EXPANDED" "$OUT/expanded.$L.png"
  sleep 5
  row "$TM" edit "$L";    sleep 2
  row "$TM" ask "$L";     sleep 2.5
  shot "$EXPANDED" "$OUT/waiting.$L.png"
  sleep 6
  shot "$COMPACT" "$OUT/compact-waiting.$L.png"
  wait
done

# ---- 动图：收起在跑 → 声明到达，从刘海往两边、再往下展开 → 6 秒后收回 ----
for L in en zh; do
  case " $PARTS " in *" motion "*) ;; *) break ;; esac
  prompts "$L"
  D="$WORK/motion-$L"
  rm -rf "$D"
  session "$D" "media-motion-$L" /work/atlas "$MAIN_PROMPT"
  TM="$D/media-motion-$L.transcript.jsonl"
  stop
  WILLOW_LANG=$L WILLOW_STATE_DIR="$D" "$BIN" --present 22 --real --passive --backdrop 2>"$WORK/motion-$L.log" &
  sleep 3
  row "$TM" thinking "$L"; sleep 2
  rm -f "$WORK/motion-$L.mov"
  screencapture -x -v -V 11 -R "$EXPANDED" "$WORK/motion-$L.mov" &
  REC=$!
  sleep 1.5
  row "$TM" declare "$L"; sleep 0.8
  row "$TM" grep "$L";    sleep 0.7
  row "$TM" bash "$L";    sleep 0.8
  row "$TM" read "$L"
  wait "$REC"
  log "录屏 motion-$L.mov"
  wait
  ffmpeg -loglevel error -y -i "$WORK/motion-$L.mov" \
    -vf "fps=15,scale=680:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=160:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
    "$OUT/expand.$L.gif"
  log "动图 expand.$L.gif"
done

echo "=== 日志 ==="; tail -n 6 "$WORK"/*.log
ls -la "$OUT"
