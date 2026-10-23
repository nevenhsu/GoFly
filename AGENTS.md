# Project instructions

This workspace contains the local REA research environment. The research target
and implementation specification have not been selected yet.

- Follow the user's current request and preserve unrelated work.
- When confirmed design or interaction requirements change, including Figma-only
  work, update the related development specifications, terminology, and acceptance
  criteria in the same task. Replace superseded rules and distinguish design
  updates from implemented behavior and device verification.
- Figma work is currently limited to UI/UX wireframes. Unless the user explicitly
  requests prototypes again, do not add prototype wiring, interaction tests, or
  combinatorial state screens. Keep only the wireframes needed for discussion.
- Source `scripts/env.sh` for the project's JDK 21 and Ghidra paths.
- For reverse-engineering tasks, read `tools/reverse-skill/README_AI.md`,
  `tools/reverse-skill/RULES.md`, and `tools/reverse-skill/skills/SKILL.md`.
  Resolve package-relative references from that repository, and invoke its
  scripts through their actual paths under `tools/reverse-skill/skills/scripts/`.
- Reverse-skill is shared with Codex and Claude through the
  `~/.agents/skills/reverse-skill-router` symlink. Keep package rules in the
  skill rather than copying them into global agent rules.
- Use REA for analysis and preserve evidence and unknowns under `work/`.
- Choose target-specific tools after the user selects a target. PentAGI model
  credentials and testing scope must be configured before a security test.
- Keep credentials and generated research output out of version control.
- Do not run Prettier unless explicitly requested.

## iOS 實機測試安裝

- 實機測試安裝／更新一律使用 `bash scripts/install-ios-test.sh`，或相同的正式 Mac setup producer；不可只執行 Xcode／`devicectl install` 後宣告完成。先指定並核對 USB 裝置與既有簽署 Team，`--action preflight` 唯讀檢查後，已有使用者安裝授權才執行 `--action apply`。
- 首次 `--mode install`；已有 App 使用預設 `--mode renew`。兩者都須確認 App、這支手機的配對匯入與必要裝置支援；重新簽名／更新也不能略過配對。不卸載、不清除偏好設定／最愛／路線，不為了成功更換 Team。
- 寫入中斷保留原 `setupID`，用同一腳本 `--action status` 核對；只有明確可續時才 `--action resume`，不可另開交易盲目重送。操作範例與限制見 `docs/AI-INSTALL.md`；可直接交給 AI 的覆蓋安裝任務 prompt 位於該文件的 `iOS device-test prompt` 節。
