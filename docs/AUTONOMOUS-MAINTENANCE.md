# Autonomous maintenance

Doors uses complementary free GitHub automation rather than allowing two bots to edit the same dependency source.

## One-time activation

Install the free [Renovate GitHub App](https://github.com/apps/renovate/installations/new) for **only** `mheci/doors`. The committed `renovate.json` is already its required configuration; no Renovate token, self-hosted runner, or repository secret is needed.

GitHub-native Dependabot starts from `.github/dependabot.yml` automatically. Repository security features and the `ghcr-publish` environment are configured separately in GitHub settings because they are not source-controlled.

## Ownership split

| Maintainer | Owns | Cadence | Merge behavior |
| --- | --- | --- | --- |
| Dependabot | SHA-pinned GitHub Actions references | Daily, 01:15 UTC; version releases have a 7-day safety cooldown (security updates are not delayed) | Enables GitHub native squash auto-merge |
| Renovate | All other supported dependency managers plus the custom BlueBuild CLI and Trivy release references | Weekday schedule set by Renovate | Enables GitHub native squash auto-merge |
| GitHub Actions | Dependency review, Scorecard SARIF, source/secret/policy validation, and image verification | PR-triggered plus scheduled checks | Never bypasses a failed check |

Renovate explicitly disables its `github-actions` manager. Dependabot is the only bot allowed to change Action pins, so duplicate update PRs are avoided.

## Autonomous merge guardrails

Both bots request **GitHub native auto-merge**, not a direct push. The protected `main` branch requires the `policy`, `image`, and `dependency-review` checks to pass and be current. A dependency PR remains open or is rebased when a check fails; no bot can bypass branch protection, force-push `main`, or move an image tag itself.

The no-publish image build uses an ephemeral signing key. Only an approved trusted-main/scheduled run can reach the separate `ghcr-publish` environment and publish `ghcr.io/mheci/doors:latest`.

## Ongoing unattended chores

- Dependabot security updates and dependency alerts use GitHub's advisory data.
- The Dependency Review workflow checks every pull request against GitHub advisory data.
- OpenSSF Scorecard runs weekly and uploads SARIF findings to GitHub code scanning.
- The policy workflow runs daily, including Actionlint, ShellCheck, Zizmor, a full-history Gitleaks scan, and the image-contract validator.
- The image workflow retains its Monday 00:00 UTC publication cadence. A temporary Bazzite-base or package-metadata failure receives one delayed retry and then fails closed; each compose job has a four-hour ceiling so a stalled upstream build cannot block maintenance indefinitely. The final SBOM/provenance gate runs on a fresh runner against the resolved immutable digest, with checksum-verified Trivy image analysis limited to one worker. It is never worked around by a kernel pin, repository bypass, a second NVIDIA path, or a skipped attestation.

## Operational expectation

Autonomy means routine dependency PRs are created, kept current, and merged once required checks are green. It does not turn an upstream package conflict or a failed physical hardware gate into a successful release. Those conditions remain deliberately fail-closed.
