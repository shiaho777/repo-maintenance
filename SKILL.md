---
name: repo-maintenance
description: Use when the user asks to maintain repositories, contribute upstream, land open-source PRs, check PR readiness, triage a pulls inbox, run repo-maintenance, or says "dedicate your hearts". Chooses living App and AI products. Always ask which mode first — home turf, PR gate, discovery, or inbox.
---

# Repo Maintenance

An autonomous open-source contribution system with four modes sharing one faith: you act as a dedicated maintainer of whichever project you land in — find real problems, fix them properly, upstream the work. You are not farming PRs; you are making projects genuinely better. The mindset never changes between modes — only the workflow does.

Influence is a repeated name on a few living products, not one PR on many strangers. A merged fix users will hit is the unit of work. An open PR is not.

## Step 0 — Always ask the mode first

On invocation, check the inbox, then ask which mode to run (use `ask_user_question` if available):

```bash
gh search prs --author @me --state open --limit 20 \
  --json repository,number,title,reviewDecision,url
```

If any open PR has `reviewDecision` `CHANGES_REQUESTED`, say so and put **Inbox sweep** first. Answering a review merges something you already finished. Still wait for the pick.

1. **Home turf** — deepen a repo where the user already has merged PRs
2. **PR gate** — the change is already finished; enforce submission discipline before opening the PR
3. **Product discovery** — sample App / AI verticals in Chinese and English, vet living products, present every qualifying project in one table, then let the user pick or reroll
4. **Inbox sweep** — triage the user's own open PRs: reply, fix, or close

Do not start any phase until the user picks. If the user's request already implies a mode, confirm it briefly instead of asking blind. A repo the user named is the target — do not re-hunt.

## Preconditions

- `gh` CLI authenticated (`gh auth status`). If not, stop and tell the user.
- `git` configured with the user's identity.

## One process per repo

Other sessions are running this skill at the same time, including sessions in another coding-agent harness. They must not vet, clone, or ship the same `OWNER/REPO` as you. Claims live in `~/.agents/repo-maintenance` and are shared by every harness. The only interface is:

`scripts/claim-repo.sh` beside this SKILL.md. Run that file. Do not copy it somewhere else and let the two drift.

- `claim OWNER/REPO` — execution lock. The holder is the nearest long-lived parent of the command, so it works for every harness without a name list, and it dies when that process dies. Chats that share one process are split by the session id that harness exports (`GROK_SESSION_ID`, `CLAUDE_CODE_SESSION_ID`, `CODEX_THREAD_ID`, `CODEX_SESSION_ID`). The first claim in a chat prints `acquired`. A later claim from that same chat prints `owned`. Exit 1 means a different live chat holds it. A dead holder is stolen.
- `release OWNER/REPO` — drop that lock when this process leaves the repo: target met, stop rule, cannot verify, or switching. Do not remove a lock this process does not hold.
- `seen OWNER/REPO` — Mode 3 only. Exit 0 means this process is the one that will vet and maybe show it. Exit 1 means another process already took it; skip. Seen entries stay after the work ends. Delete `~/.agents/repo-maintenance/seen` only when the user asks to reshuffle history.
- `list-active` — live execution locks, one `OWNER/REPO` per line.

`list-active` is a hint. `claim` is the gate. Start a loop only when it prints `acquired`. `owned` means this chat already holds the repo: do not start a second loop, and if this conversation never received `acquired` for it, treat that as busy and take the next repo. Exit 1 is busy. Do not clone, fetch, commit, or push before `acquired`.

## Quality universe

Apply this whenever **you** are choosing the repo. Modes 1 and 3 both use it. Do not restate the gates elsewhere.

A qualifying project is a shipping **app** (mobile, desktop, web, or a CLI people run) or an **AI product** (agent runtime, model app, inference app, or a library other software actually runs on). Skip lists, tutorials, books, roadmaps, interview notes, prompt or rule packs, starters, boilerplates, and thin "wraps X API" dumps — in English or Chinese.

Stage A drops those on name and description before any per-repo API call. Junk lexicon: `awesome`, `教程`, `tutorial`, `interview`, `面试`, `roadmap`, `boilerplate`, `starter`, `笔记`, `curated`, `prompt list`, `cheat sheet`, `学习笔记`, and names containing `/awesome-`.

Hard gates for a repo you choose:

- Not archived, not a fork, not a template repo, `has_issues` true, a SPDX license is present.
- Pushed within 7 days, and at least 2 commits in the last 30 days by a human (user type not `Bot`, login not ending in `[bot]`). A dependabot push does not count as alive.
- Stars in `200..5000` (Mode 3 only).
- Community-human merge rate on the **recent** closed-PR window: `external ≥ 5` and `pass_rate ≥ 40%` passes; `external ≥ 5` and `pass_rate < 40%` skips; `external < 5` is 样本不足 — confirm with recently merged community PRs before deciding, and do not paginate into ancient history to inflate the rate.
- Median days from open to merge on that same community-human sample: when at least 3 of them merged, median `≤ 21` days. Slower than that, maintainers will not give you a fast merge no matter how good the patch is.
- At least one community-unassigned, non-PR issue a maintainer could merge a fix for. A tracker made of questions, typos, and bare feature wishes fails.
- README shows a real product and a way to build or test it. CONTRIBUTING is optional — absence is neutral. "Only accepts plugins", "no external feature PRs", or hostile terms → skip.
- You can run that build or test here. If a real attempt cannot verify the change, drop the repo and pick another. An unverified PR is an unfinished one.

Mode 1 exceptions, and only these: the star band does not apply; last push may be 30 days rather than 7; a repo the user already merged into may be adopted with an empty community tracker when you can name a concrete user-facing defect. Do not invent one to qualify.

An explicit repo from the user skips the hunt and the star band. Still stop for archived, `has_issues: false`, or a list / tutorial / prompt pack, and say which gate failed.

## Mode 1 — Home turf

1. Count merged PRs per repo, most first:
   `gh search prs --author @me --merged --limit 200 --json repository --jq '.[].repository.nameWithOwner' | sort | uniq -c | sort -nr`
2. Skip anything `list-active` prints. Walk from the top and take the first remaining repo that passes the Quality universe under the Mode 1 exceptions. Use the actionable-issue sample only to decide whether real work exists:
   `gh api "repos/OWNER/REPO/issues?state=open&per_page=100" | jq '[.[] | select((.pull_request == null) and (.assignee == null) and ((.author_association // "NONE") | IN("NONE","FIRST_TIMER","FIRST_TIME_CONTRIBUTOR","CONTRIBUTOR")))] | length'`
3. Skip repos you cannot fork, and fall to the next. Do not rank by raw open-issue count — noisy trackers win that sort and merge poorly.
4. Set up the workspace (see "Workspace setup"), then run The Maintenance Loop. If `claim` does not print `acquired`, leave that repo and try the next.
5. If none qualify, list what you checked and which gate failed, then ask whether to switch to Mode 3. Never force a repo that failed the filters.

## Mode 2 — PR gate

Use when the code change is already done and the job is to submit it properly.

1. Identify the target repo and its upstream. It does not have to live under `github-xxx` — work where the work lives — but fork/remote must be correct before pushing.
2. Re-verify the diff like a maintainer reviewing their own work: run the project's checks, confirm atomic commits and repo conventions, confirm the fix is complete rather than cosmetic.
3. Apply "PR text rules" and "Conduct after submitting" in full — study maintainer PR style first, plain English, results only, no issue references, no self-promotion, fill the template, then `gh pr create` autonomously.
4. Mode 2 ends at one submitted PR — the multi-PR target (default 3) belongs to Modes 1 and 3 only. Report the PR link, a summary of its text, and its status, plus the checks you ran.

## Mode 3 — Product discovery (vertical sweep → table → user picks)

Same faith, opposite direction: find one living App or AI product worth adopting, then go deep.

Each sweep picks **2** verticals at random and runs each row's Chinese and English terms in one query. Rotate `--sort` among `stars`, `updated`, and `help-wanted-issues`. Sample randomly among survivors — do not take the first hit.

| 方向 | 检索词（中英同一条查询） |
|---|---|
| AI 智能体 | `智能体 OR "AI agent" OR "ai agent" OR topic:ai-agents OR topic:llm-agent` |
| 大模型应用 | `大模型 OR "large language model" OR topic:llm OR topic:large-language-models` |
| 本地模型应用 | `本地大模型 OR "local llm" OR ollama OR "llama.cpp"` |
| 安卓应用 | `安卓应用 OR "android app" OR topic:android-app OR topic:android-application` |
| 跨端应用 | `topic:flutter OR topic:jetpack-compose OR "compose multiplatform" OR 跨平台应用` |
| AI 客户端 | `"AI app" OR "AI 应用" OR "LLM app" OR topic:chatgpt` |

Stage A — search, then drop junk and already-seen repos locally. No per-repo API yet:

```bash
SINCE_7D=$(date -u -v-7d +%Y-%m-%d 2>/dev/null || date -u -d '7 days ago' +%Y-%m-%d)
QUAL="stars:200..5000 fork:false archived:false pushed:>=$SINCE_7D"
# TOPIC is one vertical row. Rotate --sort among stars, updated, help-wanted-issues.
gh search repos "$TOPIC $QUAL" --sort updated --order desc \
  --json fullName,description,stargazersCount,forksCount,url,pushedAt,language \
  --limit 50
```

Merge the two verticals, `unique_by(.fullName)`, drop the junk lexicon, drop anything `list-active` prints, then shuffle. Before any per-repo API call, `seen` that survivor. Exit 1 means another process took it; skip. That call is what keeps two sessions from vetting and showing the same repo.

Stage B — spend the Quality universe API calls only on shuffled survivors, several at a time, and **stop at 10 passes**. Do not deep-fetch a whole search page.

```bash
SINCE_30D=$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)

# Metadata. Search JSON has no topics, license, fork, or template bit, and its counts go stale.
gh api "repos/OWNER/REPO" --jq '{stars: .stargazers_count, forks: .forks_count, language: .language, topics: .topics, has_issues: .has_issues, archived: .archived, fork: .fork, is_template: .is_template, license: .license.spdx_id, default_branch: .default_branch, pushed_at: .pushed_at}'

# Recent window only — do not paginate into older PRs. Bots merge automatically and inflate the rate.
# Numbers only; label them from the Quality universe. A null author_association cannot tell
# who is external — sample 30 with `gh pr view` instead of coercing it to NONE.
gh api "repos/OWNER/REPO/pulls?state=closed&per_page=100" --jq '
  if any(.[]; .author_association == null) then {error: "no author_association"}
  else
    [.[] | {merged: (.merged_at != null), assoc: .author_association,
            bot: ((.user.type == "Bot") or (.user.login | endswith("[bot]"))),
            days: (if .merged_at then (((.merged_at | fromdateiso8601) - (.created_at | fromdateiso8601)) / 86400 | floor) else null end)}]
    | map(select((.assoc | IN("NONE","FIRST_TIMER","FIRST_TIME_CONTRIBUTOR","CONTRIBUTOR")) and (.bot | not)))
    | {external: length, merged: (map(select(.merged)) | length),
       median_days: ([.[] | select(.days != null) | .days] | if length == 0 then null else (sort | .[(length / 2) | floor]) end)}
    | . + {pass_rate: (if .external > 0 then ((.merged * 100 / .external) | floor) else null end)}
  end'

# Alive = human commits, not the push timestamp. First page is enough for the >= 2 gate.
gh api "repos/OWNER/REPO/commits?since=$SINCE_30D&per_page=100" --jq '
  [.[] | select(.author != null and .author.type != "Bot" and (.author.login | endswith("[bot]") | not))] | length'

# Activity column — paginate. An unpaginated call caps at 30 and understates busy repos.
gh api "repos/OWNER/REPO/commits?since=$SINCE_30D&per_page=100" --paginate --jq 'length' | awk '{s+=$1} END {print s}'

# Demand. Full pagination is too slow; pair the search total with a 100-issue sample.
gh api "search/issues?q=repo:OWNER/REPO+type:issue+state:open" --jq .total_count
gh api "repos/OWNER/REPO/issues?state=open&per_page=100" | jq '{community_unassigned: ([.[] | select((.pull_request == null) and (.assignee == null) and ((.author_association // "NONE") | IN("NONE","FIRST_TIMER","FIRST_TIME_CONTRIBUTOR","CONTRIBUTOR")))] | length)}'

gh api -H "Accept: application/vnd.github.raw" "repos/OWNER/REPO/readme" | head -40
```

### Present the batch — mandatory gate

Once 10 projects pass, list ALL of them. No truncation, no "top 3", no prose in place of rows:

| # | 项目名称 | Star | Fork | 通过率 | 合并耗时 | 活跃度 | 待办 issue | 项目内容 |
|---|---|---|---|---|---|---|---|---|
| 1 | [OWNER/REPO](url) | 1234 | 210 | 22/24 · 91%（欢迎外部PR） | 4天 | 1天前 · 近30天 80 commits（人类 28） | 社区 12 / 总计 40 | what the project is, 1–2 plain lines |

- 项目名称: `OWNER/REPO`, linked.
- 通过率: community-human merged/closed in the recent window, e.g. `22/24 · 91%（欢迎外部PR）`; `—（样本不足）` when fewer than 5.
- 合并耗时: median days from open to merge in that sample; `—` when unknown.
- 活跃度: days since last push, paginated commits in 30 days, and the human count from the first page.
- 待办 issue: community-unassigned non-PR issues in the first 100, against the true open-issue total.
- 项目内容: what it is and what it does. Plain, factual.

If fewer than 10 pass, say so and show near-misses in a second table with the failing gate. Widen at most 3 times, in order: a fresh pair of verticals → `stars:200..8000` → `pushed:>=<14 days ago>` and median merge days `≤ 45`. Never drop the product check, the human-commit check, the license, or the merge-rate floor, and never go below 200 stars. After 3 rounds, deliver the honest N. Never pad with failures.

### Then ask — mandatory

After the table, call the question tool and offer:

- `1` … `N` — one option per row, labelled `<#>. OWNER/REPO (★star · 合并耗时)` so the choice is unambiguous.
- `换一批` — discard the batch, sweep two different verticals, present a new table, ask again.

Do not clone, fork, or start The Maintenance Loop before the user answers. A `换一批` loops this gate until a number is picked.

### When a number is picked

Re-check the Quality universe at pick time. If the repo no longer passes, say which gate failed and ask again. Then set up the workspace like Mode 1 and run The Maintenance Loop. If `claim` does not print `acquired`, say who holds it and ask for another row. Do not clone. The PR target is unchanged (default 3).

## Mode 4 — Inbox sweep

Triage the user's own PR inbox.

1. `gh search prs --author @me --state open --json repository,number,title,url --limit 50`
2. For each open PR:
   `gh pr view NUM --repo OWNER/REPO --json reviews,comments,statusCheckRollup,state,mergeable`
3. Act per PR:
   - Review feedback or questions waiting on you → do the requested work, push, reply.
   - Failing checks you can fix → fix and push.
   - Clearly rejected or declined (maintainer said no, wontfix, superseded) → close it yourself, politely:
     `gh pr close NUM --repo OWNER/REPO --comment "<short gracious close>"`
   - Nothing needed → leave it alone.
4. Reply style: detailed enough to be useful, concise enough to respect reviewers' time. Friendly, focused, professional. Plain English.
5. Never comment on other people's issues or PRs — your own threads only. Then report what you found and did, per PR.

## Workspace setup (Modes 1 & 3)

- `claim` the repo (see "One process per repo"). Continue only when it prints `acquired`.
- `mkdir -p ~/Desktop/github-xxx`
- `git clone https://github.com/OWNER/REPO ~/Desktop/github-xxx/REPO-main`
- If `REPO-main` already exists: `cd` in only after `claim` printed `acquired`, then `git fetch origin`, checkout the default branch, pull. A checkout on disk is not a claim. Other `*-main` folders are previous runs — never touch them.
- `gh repo fork OWNER/REPO --clone=false`, wire the fork remote. Fully autonomous — never ask before forking, pushing, or opening a PR.

## The Maintenance Loop (Modes 1 & 3)

### Understand before you judge

- Read README, CONTRIBUTING, docs/, build/test setup, CI config. Learn the conventions your work will be held to.
- Skim a few recently merged external PRs and the PR template. Mirror that shape later.
- Confirm the verification command runs. If it cannot, `release` the repo, leave before writing a fix, and take the next candidate. Do not switch to a cosmetic PR to make the clone worth it.

### Mine the issues

- `gh api "repos/OWNER/REPO/issues?state=open&per_page=100" --jq '[.[] | select(.pull_request == null) | {number, title, user: .user.login, assoc: .author_association, updated: .updated_at, assignee: .assignee.login}]'`
- Read for a mergeable fix, in this order. Stop at the first one you can reproduce on HEAD and finish in this session:
  1. Crash, data loss, or a security bug you can reproduce.
  2. A regression, with a failing test you will add.
  3. A user-facing bug with an obvious expected behavior, reproduced.
  4. A broken build or test that blocks contributors, when the fix is about the product.
  5. A small behavior gap a maintainer has already agreed to in a comment on that issue.
- Community reports are the compass. A maintainer-filed bug with concrete expected behavior is eligible and often merges faster. Skip maintainer epics, RFCs, and tracking issues.
- Skip, without a speech: typos, formatting, dependency bumps, renames, unsolicited features, rewrites, issues you cannot reproduce, issues with an assignee, and issues that already have an open PR. Check open PRs before you claim the work.
- Prefer an issue touched in the last 180 days. Older than that is eligible only when you reproduce it on HEAD.
- The issue is a compass, not a contract. Fix the root cause completely, including adjacent breakage from that same cause. A second root cause is the next PR, not a larger diff.
- If the tracker is noise, find a real defect yourself by using the product. Do not invent one, and do not fall back to a typo.
- Feasibility check before code: a maintainer of this repo would merge this, it matches the project's direction, and nobody else has an open PR for it.

### Fix it like a maintainer

- Topic branch off the default branch. Atomic commits in the repo's commit style.
- Follow repo conventions exactly — lint, format, test layout, commit format, DCO/sign-off if required.
- One user-visible bug or one root cause per PR, small enough to review in a sitting. When the repo has tests, add one that fails before the fix.
- Run the project's own checks before pushing. A PR that fails CI on arrival is sloppy.
- Fix completely, not cosmetically.

### Ship — PR text rules (also enforced standalone by Mode 2)

- Study the maintainers' own merged PRs first (`gh pr list --repo OWNER/REPO --state merged --author OWNER --limit 10`, plus recent merges from other core maintainers). Mirror their title conventions, description structure, length, and tone. If a PR template exists, fill it — do not invent your own format.
- Non-negotiable text rules:
  - Plain English only.
  - State what was done and what the result is. Nothing else.
  - Never mention which issue inspired the work; never narrate process.
  - No self-promotion — no "high-value", "major", "important" claims in title or body.
  - Detailed is welcome; filler is not. Every sentence must carry reviewer-relevant information.
  - Follow CONTRIBUTING.md if present; otherwise write a normal professional PR.
- `gh pr create --repo OWNER/REPO --head USER:BRANCH --title ... --body ...`

### Conduct after submitting

- Never comment on issues — not even the one that led to the work. Never comment on other people's issues or PRs. Your own PR thread is the only place you speak.
- A review waiting on you outranks the next PR. Do the requested change and push before opening another.
- Watch for maintainer replies (`gh pr view NUM --repo OWNER/REPO --comments`, `--json reviews`). Address review feedback properly. Only post a comment yourself if you pushed changes that need explanation — otherwise stay silent.

### Land N PRs, then report

- Default target is 3 PRs on **this** repo; if the user asked for a different number, use theirs. Repeat the loop until the target is met or a stop rule fires.
- Stop the series on this repo when a maintainer rejects the approach as unwanted, or asks you to stop. `release` the repo, report that, and ask whether to switch. Do not open the rest anyway.
- After the first PR, your own reading of the product may beat the tracker — use it, still inside the work order above.
- Keep the PRs independent and atomic; each must stand on its own.
- `release` the repo before the report. A finished session must not leave a live lock.
- Report only after the target is met or a stop rule fires:
  - Each PR link
  - A summary of each PR's text content
  - Each PR's status at report time (`gh pr view NUM --repo OWNER/REPO --json state,isDraft,reviews`)
  - The checks you ran for each PR and their results — the build / test / lint commands and whether they passed. The user needs this to judge whether a PR is actually safe, not merely open.

## Standing orders — one faith across all four modes

- You are not answering an exam. Nobody grades issue-matching. Real products have real defects and you can fix them.
- If the change you are about to open is not in the work order under Mine the issues, stop and pick one that is.
- Never fabricate problems, never fake fixes, never claim work you did not do, never pad diffs. Deceiving maintainers is the one unforgivable failure.
- Stay on the repo that merges you. Do not open a second front while this one still has reviewable bugs and a maintainer who responds.
- Act with the care of an absolute maintainer, but remember the repo is not yours — respect scope, conventions, and review outcomes.
- Dedicate your hearts. Every PR should be one you would proudly defend in review.
