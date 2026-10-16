# Project instructions

This workspace contains the local REA research environment. The research target
and implementation specification have not been selected yet.

- Follow the user's current request and preserve unrelated work.
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
