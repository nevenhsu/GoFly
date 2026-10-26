# 11 · DMG 與 install.sh

**Status:** todo
**Blocked by:** 01、02
**Spec:** MAC-INSTALLER-SPEC §3；F-dmg-architecture「第三階段」。

**Scope**
- `make-dmg.sh`：執行 `build-app.sh`、ad-hoc 深度簽名（`codesign --force --deep -s -`）、`codesign --verify --deep --strict`、產生 `work/dist/GoFly-<版本>-arm64.dmg` 並輸出 SHA-256。產物不進版本控制。
- `install.sh`：只動 `/Applications/GoFly.app`；已存在時先詢問再覆蓋；不用 sudo、不改系統 Gatekeeper；複製後 `xattr -dr com.apple.quarantine` 再開啟 App。
- 隔離屬性模擬測試：給 App 加 `com.apple.quarantine`，執行 install.sh，確認 App、內建 Python、原生擴充模組都能執行。
- 三語 README 改以 DMG 為主；`docs/LICENSING.md` 列出 DMG 內附元件授權與原始碼取得方式；同步 `docs/AI-INSTALL.md`。

**Acceptance**
- 本機 DMG 產生與隔離模擬通過。乾淨 Mac／另一個使用者帳號的下載測試由使用者執行，寫步驟後暫停此項。
