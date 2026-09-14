# Development conventions

SimRecipes is developed as a private, proprietary monorepo. The repository
does not grant an open-source license.

## Branches and commits

Implementation work starts from `main` on one branch per GitHub issue. Include
the issue number in the branch name where practical, for example
`feat/12-recipe-editor` or `fix/27-image-cache`. Use English for branch names,
commits, pull requests, source code, and documentation.

Use Conventional Commits where practical:

- `feat(api): add health endpoint`
- `fix(ios): preserve offline recipe data`
- `test(api): cover private recipe authorization`
- `docs(camera): record protocol findings`
- `ci: add backend quality gates`

Do not include credentials, generated build artifacts, or automated-assistant
attribution in Git history. Never include vendor-specific secrets or signing
material in the repository.

## Pull requests and review

Every implementation pull request must address one issue, include `Closes
#<issue-number>`, describe validation performed, and identify any remaining
hardware or environment limitations. Reviewers should check the acceptance
criteria, relevant tests, API compatibility, security/privacy boundaries, and
scope for unrelated changes.

The repository-wide engineering rules in `AGENTS.md` are authoritative. The
pull request template turns the required review checks into a repeatable
checklist.

## Tests and local configuration

Run the checks relevant to the changed area before opening a pull request:

- backend formatting, static analysis, feature/unit tests, and database checks;
- iOS formatting/build/tests for affected targets;
- Docker configuration/build validation when infrastructure changes.

## GitHub Actions cost control

The workflows use path filters so that changes are validated only by the
checks they can affect:

| Changed paths | Workflow |
| --- | --- |
| `backend/**`, Composer/PHPUnit/PHPStan configuration | Backend quality |
| `backend/**` or `docker/**` | Docker quality |
| `ios/**` | iOS quality |

Each workflow cancels an older run for the same pull request when a newer
commit arrives. The Docker check does not force a fresh base-image pull, and
the iOS check uses the test action as the build-and-test validation because
tests build the application target first.

Validation is PR-first: merges do not start a duplicate `push` run on `main`
because the pull request is tested against GitHub's merge revision. Use the
manual `workflow_dispatch` trigger when a deliberate post-merge validation is
needed.

When a workflow is intentionally skipped, GitHub still shows the workflow
trigger decision in the pull request. The repository currently has no branch
protection rules that require skipped path-specific checks; if required checks
are introduced later, add a small aggregate check before making these names
mandatory.

Copy an environment example only for local use and fill it with local values.
Runtime deployment secrets belong in Coolify or another protected environment.
