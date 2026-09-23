# Autonomous maintenance

Doors uses complementary free GitHub automation rather than allowing two bots to edit the same dependency source.

## One-time activation

Install the free [Renovate GitHub App](https://github.com/apps/renovate/installations/new) for **only** `mheci/doors`. The committed `renovate.json` is already its required configuration; no Renovate token, self-hosted runner, or repository secret is needed.

GitHub-native Dependabot starts from `.github/dependabot.yml` automatically. Repository security features and the `ghcr-publish` environment are configured separately in GitHub settings because they are not source-controlled.

## Ownership split

| Maintainer | Owns | Cadence | Merge behavior |
| --- | --- | --- | --- |
| Dependabot | SHA-pinned GitHub Actions references | Daily, 01:15 UTC; version releases have a 7-day safety cooldown (security updates are not delayed) | Requests native squash auto-merge; completes an already-clean protected PR through GitHub’s PR merge API |
| Renovate | All other supported dependency managers plus the custom BlueBuild CLI and Trivy release references | Weekday schedule set by Renovate | Enables GitHub native squash auto-merge |
| GitHub Actions | Dependency review, CodeQL, Scorecard SARIF, source/secret/policy validation, and image verification | PR-triggered plus scheduled checks | Never bypasses a failed check |

Renovate explicitly disables its `github-actions` manager. Dependabot is the only bot allowed to change Action pins, so duplicate update PRs are avoided.

## Autonomous merge guardrails

Both bots use GitHub pull-request merge paths, never a direct push. The protected `main` branch requires the `policy`, `image`, and `dependency-review` checks to pass and be current. Dependabot's trusted default-branch helper resolves the completed build's immutable head SHA through GitHub's pull-request API (the `workflow_run.pull_requests` field is not relied on), then requests native auto-merge for a validated same-repository Dependabot PR. GitHub rejects that request once a PR is already clean, so the helper instead submits a SHA-bound ordinary squash PR merge; GitHub re-enforces the same current-head and branch-protection rules. GitHub deliberately suppresses recursive `push` workflow runs for a merge made with `GITHUB_TOKEN`, so a separate trusted reconciliation workflow verifies that the exact current `main` tip is a merged same-repository Dependabot PR and dispatches any missing stable-build or policy run. It never checks out PR code, reruns a failure, or publishes a stale ref. Trusted-main and scheduled reconciliation make this idempotent if an event is delayed. A dependency PR remains open or is rebased when a check fails; no bot can bypass branch protection, force-push `main`, or move an image tag itself.

The no-publish image matrix uses ephemeral Cosign and MOK signing keys. Only trusted `main` can reach the separate `ghcr-publish` environment, where the protected production Cosign and MOK PEM secrets are supplied only to BlueBuild publication actions: normal trusted-main runs publish the stable GNOME, COSMIC, and Kinoite images, while the isolated daily workflow publishes only `ghcr.io/mheci/doors:staging`.

## Ongoing unattended chores

- Dependabot security updates and dependency alerts use GitHub's advisory data.
- The Dependency Review workflow checks every pull request against GitHub advisory data.
- CodeQL analyzes GitHub Actions workflows on every pull request and trusted-main change, plus weekly scheduled coverage; it uses the security-extended query suite without executing image or PR payload code.
- OpenSSF Scorecard runs weekly and uploads SARIF findings to GitHub code scanning.
- The policy workflow runs daily, including Actionlint, ShellCheck, Zizmor, a full-history Gitleaks scan, and the image-contract validator.
- Trusted-main image publication composes the Fedora 44 Silverblue, COSMIC, and Kinoite NVIDIA Open recipes. A separate daily 03:20 UTC workflow composes only the GNOME staging recipe and verifies under a shared publication lock that it did not alter `doors:latest`. A future Fedora major needs an explicit reviewed change. A temporary base or package-metadata failure receives one delayed retry and then fails closed; each compose job has a four-hour ceiling so a stalled upstream build cannot block maintenance indefinitely. Each image hands its immutable identity to a fresh runner for checksum-verified single-worker Trivy SPDX analysis and GitHub OIDC provenance/SBOM attestations. It is never worked around by a kernel pin, repository bypass, a second NVIDIA path, a Secure Boot bypass, or a skipped attestation.

## Operational expectation

Autonomy means routine dependency PRs are created, kept current, and merged once required checks are green. This intentionally does **not** impose a mandatory human-approval gate: enforcing one would make the unattended dependency path wait for a person. Automated gates are not represented as a human code review; the corresponding Scorecard advisory is dismissed with that explicit governance rationale in GitHub code scanning. It does not turn an upstream package conflict or a failed physical hardware gate into a successful release. Those conditions remain deliberately fail-closed.
