# AI Agent Workflow — whispr-messenger/notification-service

This document describes the full development workflow an AI agent must follow
when picking up and completing a Jira ticket for this repository.

---

## 0. Prerequisites

- Jira cloud ID: `82ae2da5-7ee5-48f7-8877-a644651cd84b`
- GitHub org/repo: `whispr-messenger/notification-service`
- Default base branch: `main`
- Language: **Elixir / Phoenix** (`mix`)

---

## 1. Pick the ticket

1. Use `mcp__atlassian__getJiraIssue` to fetch the target ticket (e.g. `WHISPR-290`).
2. Read the **description**, **acceptance criteria**, and **priority** carefully.
3. Use `mcp__atlassian__getTransitionsForJiraIssue` to list available transitions.
4. Transition the ticket from "À faire" → "En cours" using `mcp__atlassian__transitionJiraIssue`
   with the transition id whose `name` is `"En cours"` (currently `"21"`).

---

## 2. Prepare the branch

```bash
git checkout main
git pull origin main
git worktree add .worktrees/<TICKET-KEY>-<short-kebab-description> -b <TICKET-KEY>-<short-kebab-description>
```

Then use the `EnterWorktree` tool to switch into the worktree:

```json
// EnterWorktree
{ "path": ".worktrees/<TICKET-KEY>-<short-kebab-description>" }
```

All subsequent work (edits, commits, pushes) happens inside the worktree. Use `ExitWorktree` when done.

Branch naming convention: `WHISPR-XXX-short-description-of-the-fix`

Example: `WHISPR-449-apns-push-notifications`

Worktrees are created in `.worktrees/` (repo-local, git-ignored) to keep the parent directory clean.

---

## 3. Implement the fix

1. Read all relevant files before modifying anything.
2. Make the smallest change that fully addresses the ticket.
3. Do not refactor unrelated code or change formatting outside the touched lines.
4. Prefer editing existing files over creating new ones.

---

## 4. Write tests

Tests live in the `test/` directory.

| Kind | Location | Pattern |
|------|----------|---------|
| Unit | `test/<module>/` | `*_test.exs` |
| Controller | `test/<app>_web/controllers/` | `*_controller_test.exs` |

### Rules

- **Test behaviour, not implementation.** Assert on observable outcomes
  (response body, HTTP status codes, database state) rather than internal call sequences.
- Use `Ecto.Adapters.SQL.Sandbox` for database isolation in tests.
- Mock external services (JWKS, Redis pub/sub) via `Mox` or process-based stubs.

### Run tests

```bash
# All tests
mix test

# Specific file
mix test test/whispr_notification/conversations_test.exs

# With coverage
mix coveralls
```

All tests must be green before committing.

---

## 5. Format and lint

```bash
# Check formatting (CI enforces this)
mix format --check-formatted

# Auto-fix formatting
mix format

# Credo strict lint
mix credo --strict
```

All three must pass before committing.

---

## 6. Commit

Stage only the files you changed:

```bash
git add <file1> <file2> ...
```

Commit message format (Conventional Commits):

```
<type>(<scope>): <short imperative summary>

<optional body — explain the why, not the what>
```

- **type**: `fix`, `feat`, `refactor`, `test`, `docs`, `chore`
- **scope**: module name, e.g. `conversations`, `messages`, `auth`
- Do **not** mention Claude, AI, or any tooling in the commit message.
- Do **not** use `--no-verify` to skip hooks.

Example:
```
feat(conversations): implement conversation search endpoint
```

### Impact on release versioning

When `deploy/preprod` is merged into `main`, the `release.yml` workflow
automatically creates a Git tag and GitHub Release. The version number follows
**Semantic Versioning** and is determined by scanning commit messages since the
last tag:

| Commit pattern | Version bump | Example |
|----------------|-------------|---------|
| `<type>(<scope>)!:` or body contains `BREAKING CHANGE` | **major** (`x.0.0`) | `feat(redis)!: remove legacy connection mode` |
| `feat(<scope>):` | **minor** (`0.x.0`) | `feat(notifications): add APNs push support` |
| Any other type (`fix`, `refactor`, `test`, `docs`, `chore`, …) | **patch** (`0.0.x`) | `fix(redis): pass username in AUTH command` |

The highest bump wins: if the range contains both a `feat` and a `fix`, the
version bumps **minor**. If any commit is a breaking change, it bumps **major**.

> **Rule of thumb**: use `feat` only for new user-facing functionality, not for
> internal refactors or test additions. A misplaced `feat` prefix triggers a
> minor bump instead of a patch.

---

## 7. Push

```bash
git push -u origin <branch-name>
```

After every push to an existing PR branch, **immediately**:

1. Request a Copilot review using `mcp__github__request_copilot_review`:

```json
// mcp__github__request_copilot_review
{
  "owner": "whispr-messenger",
  "repo": "notification-service",
  "pullNumber": <number>
}
```

2. CI runs `mix compile --warnings-as-errors` — any warning is a build failure. Fix all compiler warnings before pushing.

3. Check CI with:

```bash
gh pr checks <PR-number> --repo whispr-messenger/notification-service
```

Fix any failing checks before proceeding.

---

## 8. Open a Pull Request

Use `mcp__github__create_pull_request`:

```json
{
  "owner": "whispr-messenger",
  "repo": "notification-service",
  "title": "<same as commit title>",
  "head": "<branch-name>",
  "base": "main",
  "body": "## Summary\n- bullet 1\n- bullet 2\n\n## Test plan\n- [ ] mix test green\n- [ ] mix format --check-formatted clean\n- [ ] mix credo --strict clean\n\nCloses <TICKET-KEY>"
}
```

After creation, request a Copilot review immediately using `mcp__github__request_copilot_review`:

```json
{
  "owner": "whispr-messenger",
  "repo": "notification-service",
  "pullNumber": <number>
}
```

Then check CI with:

```bash
gh pr checks <PR-number> --repo whispr-messenger/notification-service
```

Fix any failing checks before moving to §8b.

---

## 8b. Process review comments

GitHub Copilot reviews the PR automatically on each push. Repeat the loop below
until no unresolved, non-outdated threads remain.

### Fetch open threads

Use `mcp__github__pull_request_read` with `method: "get_review_comments"`.
Filter to threads where **`is_resolved: false`** and **`is_outdated: false`**.

### For each open thread

1. **Read the comment carefully** — note whether it is labelled Blocking or Non-blocking.
2. **Decide**:
   - **Fix** — implement the change, commit, then reply citing the commit hash and what was done.
   - **Acknowledge / Won't fix** — reply with a clear rationale.
3. **Reply in the thread** using `mcp__github__add_reply_to_pull_request_comment`
   with `commentId` set to the ID of the **first** comment in the thread.

### Severity guide

| Label | Action |
|-------|--------|
| **Blocking** | Must be fixed or explicitly declined with justification before merge |
| **Non-blocking** | Should be fixed or acknowledged; declining is acceptable with rationale |
| *(unlabelled)* | Style/tidiness — fix if trivial, acknowledge otherwise |

### Push and re-check

After addressing all open threads, push:

```bash
git push origin <branch-name>
```

Then immediately request a new Copilot review:

```json
// mcp__github__request_copilot_review
{
  "owner": "whispr-messenger",
  "repo": "notification-service",
  "pullNumber": <number>
}
```

Copilot will review the updated diff and may open new threads. Re-run this step
until `get_review_comments` returns no unresolved, non-outdated threads.

### Merge gate

- All **blocking** threads resolved (fixed or declined with justification)
- All **non-blocking** threads acknowledged
- CI green (`gh pr checks <PR-number> --repo whispr-messenger/notification-service`)

---

## 9. Merge the PR

Once all CI checks are green, use `mcp__github__merge_pull_request`:

```json
{
  "owner": "whispr-messenger",
  "repo": "notification-service",
  "pullNumber": <number>,
  "merge_method": "squash"
}
```

Always use **squash** merge to keep `main` history linear.

---

## 10. Close the Jira ticket

Use `mcp__atlassian__transitionJiraIssue` with the transition whose `name` is
`"Terminé"` (currently id `"31"`) to move the ticket to done.

---

## 11. Return to main and clean up

Use `ExitWorktree` to leave the worktree, then:

```bash
git checkout main
git pull origin main
git worktree remove .worktrees/<TICKET-KEY>-<short-kebab-description>
git branch -d <TICKET-KEY>-<short-kebab-description>
```

`git worktree remove` deletes the `.worktrees/<branch>` directory. `git branch -d` removes the local branch (the remote branch is deleted automatically by GitHub after squash merge).

---

## Jira transition IDs (current)

| Name | ID |
|------|----|
| À faire | `11` |
| En cours | `21` |
| Terminé | `31` |

These IDs are stable but can be verified with
`mcp__atlassian__getTransitionsForJiraIssue` if in doubt.

---

## Jira MCP — Usage Notes

### Tool parameter types

`mcp__atlassian__searchJiraIssuesUsingJql` requires:
- `maxResults`: **number**, not string (e.g. `10`, not `"10"`)
- `fields`: **array**, not string (e.g. `["summary", "status"]`, not `"summary,status"`)

### Fetching the sprint ID for issue creation

`mcp__atlassian__createJiraIssue` requires a **numeric** sprint ID in `additional_fields.customfield_10020`, not a name string.

To get it, query an existing issue from the target sprint and read `customfield_10020[0].id`:

```json
// mcp__atlassian__searchJiraIssuesUsingJql
{
  "jql": "project = WHISPR AND sprint in openSprints()",
  "fields": ["customfield_10020"],
  "maxResults": 1
}
// → customfield_10020[0].id  (e.g. 167 for Sprint 5)
```

Then pass it as a number in `createJiraIssue`:

```json
// mcp__atlassian__createJiraIssue
{
  "additional_fields": { "customfield_10020": 167 }
}
```

### Current sprint

| Sprint | ID | Board ID |
|--------|----|----------|
| Sprint 8 | `299` | `34` |

### Tools that do NOT work

- `mcp__atlassian__jiraRead` — requires an `action` enum parameter, not a free-form URL; not useful for agile/sprint endpoints.
- `mcp__atlassian__fetch` — requires an `id` parameter; cannot be used for arbitrary REST calls.

---

## Elixir-specific notes

### Compiler warnings are errors in CI

`mix compile --warnings-as-errors` is enforced. Common pitfalls:
- Default arguments in private functions that are never used → remove the default.
- Unused variables → prefix with `_` or remove.
- Unreachable clauses in `with` / `case` → fix the pattern.

### JWKS authentication

The service uses a custom `JwksCache` GenServer to cache public keys from the auth-service JWKS endpoint. Authentication is done via the `WhisprNotificationWeb.Plugs.Authenticate` plug. Tokens are verified with `Joken` using EC P-256 keys.

### Database

PostgreSQL via Ecto. Use `Repo.transaction/2` for multi-step operations. Never interpolate user input in raw SQL — use parameterised queries or Ecto query DSL.

### Testing database isolation

Tests use `Ecto.Adapters.SQL.Sandbox` in `:manual` checkout mode. Each test that touches the DB must call `Ecto.Adapters.SQL.Sandbox.checkout(WhisprNotification.Repo)`.

