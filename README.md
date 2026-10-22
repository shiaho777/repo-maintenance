# repo-maintenance

Agent skill for maintaining a living App or AI project: pick real defects, fix them, and open reviewable pull requests. Concurrent sessions, including different coding-agent harnesses, claim a repository before anyone clones it, so two processes do not land on the same project.

## Install

```bash
git clone https://github.com/shiaho777/repo-maintenance.git ~/.agents/skills/repo-maintenance
```

Harnesses that load `~/.agents/skills` pick it up from there. Claude Code reads `~/.claude/skills` instead:

```bash
mkdir -p ~/.claude/skills
ln -s ~/.agents/skills/repo-maintenance ~/.claude/skills/repo-maintenance
```

## Layout

- `SKILL.md` — the procedure agents follow
- `scripts/claim-repo.sh` — the cross-session claim lock

Claims and the discovery seen-set are stored in `~/.agents/repo-maintenance`.
