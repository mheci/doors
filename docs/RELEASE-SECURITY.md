# One-time GitHub and release-security setup

Repository files cannot themselves enable GitHub branch/ruleset settings. Apply these controls in **Settings → Rules → Rulesets** (or the equivalent branch-protection UI) after the first CI run reveals exact check names.

## `main` ruleset

Target the default branch `main`, enforce actively, and configure:

1. **Require a pull request before merging**. Set required approving reviews to **0** for solo, agent-assisted maintenance; require resolved conversations.
2. **Require status checks to pass and be up to date.** Require at minimum:
   - `Policy and static validation / policy`
   - `Build and publish Doors / image`
   Add the exact published-image check if the UI exposes a trusted-main-only status separately.
3. **Block force pushes and branch deletion.**
4. **Do not allow direct pushes/bypasses for routine work.** Use a PR even for the repository owner; reserve any emergency bypass for a documented incident only.
5. Do **not** require a fixed human approver count or CODEOWNER approval; that would conflict with the accepted solo-maintainer workflow. CODEOWNERS remains an assignment/review aid.

After enabling the ruleset, attempt a safe test PR and confirm that a direct push to `main` is rejected.

## GitHub Actions settings

- Set the repository’s default workflow token permissions to **read-only**.
- Permit workflow write permissions only where declared in the trusted publication job (`packages`, `id-token`, `attestations`).
- For forked pull requests, require approval before workflows run and never grant write tokens/secrets to `pull_request` workflows.
- Keep Actions restricted to reviewed actions where practical. This repository SHA-pins every action and runs `actionlint` plus `zizmor`.
- Create a `ghcr-publish` GitHub Environment and move the sole release-signing secret, `SIGNING_SECRET`, into that environment. Configure its deployment-branch policy for `main` only and do **not** require reviewers: publication is intentionally automatic every Monday at 00:00 UTC. Do not expose that environment to reusable workflows, PR contexts, logs, artifacts, or issue text.

## Package visibility and signing

- Make `ghcr.io/mheci/doors` public only after signature/provenance/SBOM verification succeeds.
- Retain the existing `cosign.pub` matching `SIGNING_SECRET`; rotate only through a dedicated reviewed migration that supports current consumers.
- Configure package permissions so only this repository’s trusted workflow can publish/delete package versions. Do not give unrelated repositories inherited administration.

## Renovate policy

Renovate may propose all supported updates, but it may auto-merge only an explicitly reviewed low-risk allowlist after required checks. The current allowlist is intentionally empty: the current dependencies are all actions, image/build-chain, signing, registry, or policy inputs. A future allowlist entry must state why it is low risk and must not cover keys, workflows, build tooling, repositories, major versions, or release policy.
