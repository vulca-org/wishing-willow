# Wishing-Willow 看板 —— 本机编译即用。
#
# 不做签名和公证：本地编译出来的二进制不带 quarantine 属性，Gatekeeper 不拦。
# 下载来的 .app 才需要那一套，而这个项目故意不走下载分发。

APP      := WishingWillow
BUNDLE   := build/$(APP).app
BIN      := .build/release/$(APP)
INSTALL  := /Applications/$(APP).app

.PHONY: all build app run install test snapshots clean

all: app

build:
	swift build -c release

app: build
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	@cp Resources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	@cp "$(BIN)" "$(BUNDLE)/Contents/MacOS/$(APP)"
	@echo "APPL????" > "$(BUNDLE)/Contents/PkgInfo"
	@echo "→ $(BUNDLE)"

run: app
	@pkill -x "$(APP)" 2>/dev/null || true
	@open "$(BUNDLE)"
	@echo "→ 看菜单栏右侧的叶子图标"

install: app
	@rm -rf "$(INSTALL)"
	@cp -R "$(BUNDLE)" "$(INSTALL)"
	@echo "→ $(INSTALL)"

# 面板的四种状态各渲一张 PNG。不需要屏幕录制权限，也不接管屏幕。
# 注意：离屏渲染没有活的合成器背景，玻璃层走的是退路（见 WillowGlass.swift），
# 所以这些图证明布局、文案和状态，不证明玻璃效果。
snapshots: build
	@./$(BIN) --snapshot snapshots
	@echo "→ macos/snapshots/"

test:
	@swift test 2>&1 | tee /tmp/willow-macos-test.log | grep -E '✔|✘|⊘|真实文件|Test run'
	@grep -q '⊘ SKIP' /tmp/willow-macos-test.log \
		&& echo "⚠ 有关卡被跳过（见上）—— 跳过不是通过" \
		|| true

clean:
	@rm -rf .build build
