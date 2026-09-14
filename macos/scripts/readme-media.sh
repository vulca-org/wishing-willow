#!/bin/bash
# README 素材：在 --backdrop 的干净底色上，用虚构的会话按真实事件顺序跑一遍灵动岛，拍中英两套静帧和三段动图（声明到达弹出精简卡、悬停长成完整面板、点开面板）。
#
#   macos/scripts/readme-media.sh [二进制]      默认 macos/.build/release/WishingWillow
#   PARTS=detail macos/scripts/readme-media.sh  只录某一段（stills / motion / hover / detail，默认全录）
#
# 输出到 docs/media/，中间文件在 macos/build/readme-media/（不进仓库）。
# 需要：屏幕录制权限（screencapture）、node、ffmpeg。会先关掉正在跑的 WishingWillow，退出时重新打开 macos/build/WishingWillow.app。
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
PARTS="${PARTS:-stills motion hover detail}"
mkdir -p "$WORK"

restore() { open "$ROOT/macos/build/WishingWillow.app" 2>/dev/null || true; }
trap restore EXIT

# 刘海在屏幕水平正中；截图区域都以它为轴。
W=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var s = $.NSScreen.screens; var f = s.objectAtIndex(0).frame; f.size.width')
C=$(python3 -c "print(int(float('$W') / 2))")
# 主动弹出的精简卡约 440×79pt，完整悬停面板长会话约 360pt 高（2026-09-13 实拍），各留一圈余量。
POPUP="$((C - 280)),0,560,100"
PANEL="$((C - 340)),0,680,430"
COMPACT="$((C - 300)),0,600,96"
DETAIL="$((C - 350)),0,700,510"

log() { echo "$(date +%H:%M:%S) $*"; }
now() { python3 -c 'import datetime;print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3]+"Z")'; }
stop() { pkill -x WishingWillow 2>/dev/null || true; pkill -f "WishingWillow.release" 2>/dev/null || true; sleep 0.8; }
shot() { rm -f "$2"; screencapture -x -R "$1" "$2"; log "静帧 $(basename "$2")"; }

# 录屏会把鼠标指针一起录进去（2026-09-13 点击面板动图左下角有指针）。开 app 之前先等指针离开录制区域，最多 20 秒。
bright() {  # $1 png → 画面中部亮像素数；纯黑面板约为 0
  ffmpeg -loglevel error -i "$1" -vf "crop=iw*0.6:ih*0.55:iw*0.2:ih*0.15,format=gray" -f rawvideo - \
    | python3 -c "import sys; d=sys.stdin.buffer.read(); print(sum(1 for b in d if b > 90))"
}

cursor_clear() {  # $1 区域 x,y,w,h（点，顶边为 0）
  local i=0
  while [ $i -lt 40 ]; do
    if osascript -l JavaScript -e "ObjC.import('AppKit'); var p = \$.NSEvent.mouseLocation; var h = \$.NSScreen.screens.objectAtIndex(0).frame.size.height; var r = '$1'.split(',').map(Number); var y = h - p.y; (p.x < r[0] || p.x > r[0] + r[2] || y < r[1] || y > r[1] + r[3]) ? 'out' : 'in'" | grep -q out; then
      return 0
    fi
    [ $i -eq 0 ] && log "鼠标在录制区域里，等它离开"
    sleep 0.5; i=$((i + 1))
  done
  log "鼠标 20 秒没离开录制区域，照录——动图里会有指针"
}

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
# 插件现在要求四行（第三行「我补上的」灵动岛不显示，但解析不能被它带偏）。
declare = ("你批准的：只找出上传测试为什么只在 CI 上失败，不改代码。\n"
           "我读成了：重写上传测试的重试逻辑，把不稳定的测试修好。\n"
           "我补上的：把「找原因」扩成「修好」；改动范围定为 retry.go。\n"
           "标签：修上传测试") if zh else (
           "You approved: find out why the upload test fails only on CI, without changing code.\n"
           "How I read it: Rewrite the upload test’s retry logic so it stops flaking.\n"
           "What I filled in: widened “find the cause” to “fix it”; scoped the change to retry.go.\n"
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

# ---- 静帧：收起（在跑 + 胶囊）→ 声明到达弹出精简卡 → 等你选择弹出题面 → 收起（问号计时） ----
#      精简卡弹出 6 秒后自己收回，所以两张弹出图都在到达后一两秒内拍。
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
  row "$TM" declare "$L"; sleep 1.2
  shot "$POPUP" "$OUT/popup.$L.png"
  row "$TM" grep "$L";    sleep 0.7
  row "$TM" bash "$L";    sleep 0.8
  row "$TM" read "$L";    sleep 5
  row "$TM" edit "$L";    sleep 2
  row "$TM" ask "$L";     sleep 1.5
  shot "$POPUP" "$OUT/waiting.$L.png"
  sleep 7
  shot "$COMPACT" "$OUT/compact-waiting.$L.png"
  wait
done

# ---- 动图：收起在跑 → 声明到达，从刘海弹出精简卡 → 6 秒后收回 ----
for L in en zh; do
  case " $PARTS " in *" motion "*) ;; *) break ;; esac
  prompts "$L"
  D="$WORK/motion-$L"
  rm -rf "$D"
  session "$D" "media-motion-$L" /work/atlas "$MAIN_PROMPT"
  TM="$D/media-motion-$L.transcript.jsonl"
  stop
  cursor_clear "$POPUP"
  WILLOW_LANG=$L WILLOW_STATE_DIR="$D" "$BIN" --present 22 --real --passive --backdrop 2>"$WORK/motion-$L.log" &
  sleep 3
  row "$TM" thinking "$L"; sleep 2
  rm -f "$WORK/motion-$L.mov"
  screencapture -x -v -V 11 -R "$POPUP" "$WORK/motion-$L.mov" &
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
    -vf "fps=15,scale=560:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=160:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
    "$OUT/expand.$L.gif"
  log "动图 expand.$L.gif"
done

# ---- 悬停：精简卡 → 鼠标停上去长成完整面板；录动图并拍一张完整面板 ----
#      非 passive（素材录制时真鼠标的悬停一律不理）：第 8.5 秒 --flash 弹出精简卡，第 10.5 秒 --flash-hover 模拟停上去，第 14.5 秒退出。
#      时序与 social/2026-09/record.sh 的 hover 段相同。两个会话在跑，面板底部才有翻页那一行。
for L in en zh; do
  case " $PARTS " in *" hover "*) ;; *) break ;; esac
  prompts "$L"
  D="$WORK/hover-$L"
  rm -rf "$D"
  session "$D" "media-hover-$L" /work/atlas "$MAIN_PROMPT"
  session "$D" "media-hover-other-$L" /work/billing "$OTHER_PROMPT"
  TM="$D/media-hover-$L.transcript.jsonl"; TO="$D/media-hover-other-$L.transcript.jsonl"
  row "$TO" other "$L"; row "$TM" thinking "$L"
  row "$TM" declare "$L"; row "$TM" grep "$L"; row "$TM" bash "$L"; row "$TM" read "$L"
  stop
  cursor_clear "$PANEL"
  WILLOW_LANG=$L WILLOW_STATE_DIR="$D" "$BIN" --present 12 --real --backdrop --flash --flash-hover 2>"$WORK/hover-$L.log" &
  APP=$!
  sleep 7.3
  rm -f "$WORK/hover-$L.mov"
  screencapture -x -v -V 6.8 -R "$PANEL" "$WORK/hover-$L.mov" &
  REC=$!
  sleep 5
  shot "$PANEL" "$OUT/expanded.$L.png"
  wait "$REC"
  log "录屏 hover-$L.mov"
  n=0; while kill -0 "$APP" 2>/dev/null && [ $n -lt 30 ]; do sleep 0.5; n=$((n + 1)); done
  if kill -0 "$APP" 2>/dev/null; then
    log "演示进程到时没退出——hover-$L 作废"
    kill "$APP" 2>/dev/null || true; sleep 1; kill -9 "$APP" 2>/dev/null || true
    rm -f "$OUT/expanded.$L.png"; exit 1
  fi
  ffmpeg -loglevel error -y -i "$WORK/hover-$L.mov" \
    -vf "fps=15,scale=680:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=160:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
    "$OUT/hover.$L.gif"
  log "动图 hover.$L.gif"
done

# ---- 点击面板：两个会话、七轮历史（写了理解 / 自标 ⚠ / 问了没写 / 没问），加一轮进行中；
#      从收起态直接点开面板，录过渡动图并拍一张面板 ----
#      不走「悬停展开 → 再点开」：那条路径在 2026-09-13 录制时约一半次数面板整块纯黑、进程到时不退出（原因未查明，已推送的上一版同样复现）。
history() {  # $1 状态目录  $2 语言
  python3 - "$1" "$2" "$HOOKS" <<'HISTORY'
import datetime, json, os, subprocess, sys
d, lang, hooks = sys.argv[1:4]
zh = lang == "zh"
env = dict(os.environ, WILLOW_STATE_DIR=d)
now = datetime.datetime.now(datetime.timezone.utc)
iso = lambda t: t.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"

def hook(name, payload):
    subprocess.run(["node", f"{hooks}/{name}.mjs"], input=json.dumps(payload, ensure_ascii=False).encode(),
                   env=env, check=True, stdout=subprocess.DEVNULL)

def said(path, text):
    row = {"type": "assistant", "isSidechain": False, "timestamp": iso(datetime.datetime.now(datetime.timezone.utc)),
           "message": {"id": f"m-{os.urandom(4).hex()}", "role": "assistant", "model": "claude-opus-5",
                       "usage": {"input_tokens": 3, "cache_creation_input_tokens": 1800,
                                 "cache_read_input_tokens": 300000, "output_tokens": 700},
                       "content": [{"type": "text", "text": text}]}}
    with open(path, "a") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")

# (原话, 批准的, 理解, 标签, 这一轮用了多少秒)；理解为 None 且标签为 None = 没写声明（原话很短时插件根本不问）
if zh:
    sessions = {
        "media-detail-main": ("/work/atlas", [
            ("给上传命令加一个 --dry-run 参数。", "给上传命令加 --dry-run", "给上传命令加 --dry-run，只打印将要发送的内容。", "加试运行", 184),
            ("好的", None, None, None, 12),
            ("这周夜间导出为什么变慢了？先看，别改。", "只查夜间导出变慢的原因", "⚠ 给导出做性能分析并重写慢查询。", "重写慢查询", 540),
            ("把整个仓库的配置键改成 snake_case。", "配置键改成 snake_case", None, None, 95),
            ("总结一下周一以来重试模块改了什么。", "总结周一以来重试模块的改动", "列出周一以来改动 retry/ 的提交并总结。", "总结重试", 66),
        ]),
        "media-detail-other": ("/work/billing", [
            ("把账单导出改成按月分文件。", "账单导出按月分文件", "把导出拆成按月的文件。", "按月拆分", 300),
            ("旧的合并文件也保留一周。", "合并文件保留一周", "按月文件之外，合并文件再保留 7 天。", "保留合并", 140),
        ]),
    }
else:
    sessions = {
        "media-detail-main": ("/work/atlas", [
            ("Add a --dry-run flag to the upload CLI.", "add --dry-run to the upload CLI", "Add --dry-run to the upload command and print what would be sent.", "Add dry-run", 184),
            ("ok", None, None, None, 12),
            ("Why is the nightly export slower this week? Just look, don't fix.", "find why the nightly export got slower, read-only", "⚠ Profile the export and rewrite the slow query.", "Rewrite query", 540),
            ("Rename the config keys to snake_case across the repo.", "rename config keys to snake_case", None, None, 95),
            ("Summarise what changed in the retry module since Monday.", "summarise retry changes since Monday", "List the commits touching retry/ since Monday and summarise them.", "Sum up retry", 66),
        ]),
        "media-detail-other": ("/work/billing", [
            ("Split the billing export into one file per month.", "split the billing export by month", "Split the export into monthly files.", "Split export", 300),
            ("Also keep the old combined file for a week.", "keep the combined file for a week", "Keep the combined export for 7 days alongside the monthly files.", "Keep combined", 140),
        ]),
    }

for sid, (cwd, turns) in sessions.items():
    t = f"{d}/{sid}.transcript.jsonl"
    with open(t, "w") as f:
        f.write(json.dumps({"type": "assistant", "isSidechain": False, "timestamp": "2026-09-13T06:00:00.000Z",
                            "message": {"role": "assistant", "content": [{"type": "text", "text": "—"}]}}) + "\n")
    for i, (prompt, approved, read, tag, _) in enumerate(turns):
        hook("capture", {"session_id": sid, "hook_event_name": "UserPromptSubmit", "cwd": cwd,
                         "prompt_id": f"p-{sid}-{i}", "transcript_path": t, "prompt": prompt})
        if read:
            text = (f"你批准的：{approved}\n我读成了：{read}\n标签：{tag}" if zh
                    else f"You approved: {approved}\nHow I read it: {read}\nTag: {tag}")
        else:
            text = "好的，改完了。" if zh else "Done."
        said(t, text)
        hook("extract", {"session_id": sid, "hook_event_name": "Stop", "cwd": cwd, "transcript_path": t,
                         "stop_hook_active": False})
    # 钩子是一口气跑完的，真实时长都是几毫秒：把日志里的时刻挪到过去，每轮给一个不同的时长。
    log = f"{d}/{sid}.log.jsonl"
    rows = [json.loads(line) for line in open(log) if line.strip()]
    assert len(rows) == len(turns), (sid, len(rows), len(turns))
    end = now - datetime.timedelta(minutes=3)
    for row, turn in reversed(list(zip(rows, turns))):
        row["endedAt"] = iso(end)
        row["at"] = iso(end - datetime.timedelta(seconds=turn[4]))
        end -= datetime.timedelta(seconds=turn[4] + 120)
    with open(log, "w") as f:
        f.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in rows)
    state = json.load(open(f"{d}/{sid}.json"))
    state.update(pid=1, updatedAt=rows[-1]["at"], turnEndedAt=rows[-1]["endedAt"])
    json.dump(state, open(f"{d}/{sid}.json", "w"), ensure_ascii=False)
    print(sid, len(rows), "turns")
HISTORY
}

for L in en zh; do
  case " $PARTS " in *" detail "*) ;; *) break ;; esac
  prompts "$L"
  D="$WORK/detail-$L"
  rm -rf "$D"; mkdir -p "$D"
  history "$D" "$L"
  # 主会话再开一轮进行中的（transcript 从头写，偏移之后只有这一轮）。
  session "$D" "media-detail-main" /work/atlas "$MAIN_PROMPT"
  TM="$D/media-detail-main.transcript.jsonl"
  stop
  cursor_clear "$DETAIL"
  # 非 passive：第 10.5 秒从收起态直接打开面板（--detail）。
  WILLOW_LANG=$L WILLOW_STATE_DIR="$D" "$BIN" --present 16 --real --backdrop --detail 2>"$WORK/detail-$L.log" &
  APP=$!
  sleep 3
  row "$TM" thinking "$L"; sleep 1.2
  row "$TM" declare "$L";  sleep 0.8
  row "$TM" grep "$L";     sleep 0.7
  row "$TM" bash "$L";     sleep 0.8
  row "$TM" read "$L";     sleep 3.3
  rm -f "$WORK/detail-$L.mov"
  screencapture -x -v -V 4.5 -R "$DETAIL" "$WORK/detail-$L.mov"
  log "录屏 detail-$L.mov"
  sleep 0.7
  shot "$DETAIL" "$OUT/detail.$L.png"
  # 不留坏素材：演示进程到时不退出（面板卡住）或拍到纯黑面板，这一段作废并停下。
  n=0; while kill -0 "$APP" 2>/dev/null && [ $n -lt 30 ]; do sleep 0.5; n=$((n + 1)); done
  if kill -0 "$APP" 2>/dev/null; then
    log "演示进程到时没退出，面板很可能卡住了——detail-$L 作废"
    kill "$APP" 2>/dev/null || true; sleep 1; kill -9 "$APP" 2>/dev/null || true
    rm -f "$OUT/detail.$L.png"; exit 1
  fi
  B=$(bright "$OUT/detail.$L.png")
  if [ "$B" -lt 2000 ]; then
    log "面板静帧几乎全黑（亮像素 $B）——detail-$L 作废"
    rm -f "$OUT/detail.$L.png"; exit 1
  fi
  log "面板静帧亮像素 $B，进程按时退出"
  ffmpeg -loglevel error -y -i "$WORK/detail-$L.mov" \
    -vf "fps=15,scale=700:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=160:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
    "$OUT/open-detail.$L.gif"
  log "动图 open-detail.$L.gif"
done

echo "=== 日志 ==="; tail -n 6 "$WORK"/*.log
ls -la "$OUT"
