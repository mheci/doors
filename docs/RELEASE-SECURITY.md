# One-time GitHub and release-security setup

Repository files cannot themselves enable GitHub branch/ruleset settings. Keep these controls in **Settings → Rules → Rulesets** (or the equivalent branch-protection UI); this document is the recovery/audit reference if they ever need to be recreated.

## `main` ruleset

Target the default branch `main`, enforce actively, and configure:

1. **Require a pull request before merging**. Set required approving reviews to **0** for solo, agent-assisted maintenance; require resolved conversations.
2. **Require status checks to pass and be up to date.** Require at minimum:
   - `Policy and static validation / policy`
   - `Build and publish Doors / image`
   - `Dependency review / dependency-review`
   Add the exact published-image check if the UI exposes a trusted-main-only status separately.
3. **Block force pushes and branch deletion.**
4. **Do not allow direct pushes/bypasses for routine work.** Use a PR even for the repository owner; reserve any emergency bypass for a documented incident only.
5. Do **not** require a fixed human approver count or CODEOWNER approval; that would conflict with the accepted solo-maintainer workflow. CODEOWNERS remains an assignment/review aid.

After enabling the ruleset, attempt a safe test PR and confirm that a direct push to `main` is rejected.

## GitHub Actions settings

- Set the repository’s default workflow token permissions to **read-only**.
- Permit workflow write permissions only where declared in the two trusted publication stages: `image-publish` has package-write access and the environment-scoped signing secret; its dependent `publish` release gate has the package/OIDC/attestation permissions needed to scan the immutable digest and upload attestations. The narrowly scoped Dependabot auto-merge job receives only `contents` and `pull-requests`; it runs only from trusted default-branch `workflow_run`, `main` push, scheduled, or manual contexts and never checks out or executes PR-controlled code. For a completed PR build it resolves the immutable parent head SHA through GitHub's pull-request API rather than trusting the often-empty `workflow_run.pull_requests` field; its trusted-main reconciliation is idempotent and still delegates every required check to GitHub native auto-merge.
- For forked pull requests, require approval before workflows run and never grant write tokens/secrets to `pull_request` workflows.
- Keep Actions restricted to reviewed actions where practical. This repository SHA-pins every action to the version tag's immutable commit; the native Gitleaks wrapper verifies its checksum before execution, while CI also runs `actionlint`, ShellCheck, and `zizmor`.
- Create a `ghcr-publish` GitHub Environment and move the sole release-signing secret, `SIGNING_SECRET`, into that environment. Configure its deployment-branch policy for `main` only and do **not** require reviewers: publication is intentionally automatic every Monday at 00:00 UTC. Do not expose that environment to reusable workflows, PR contexts, logs, artifacts, or issue text.

## Package visibility and signing

- Make `ghcr.io/mheci/doors` public only after signature/provenance/SBOM verification succeeds.
- Retain the existing `cosign.pub` matching `SIGNING_SECRET`; rotate only through a dedicated reviewed migration that supports current consumers.
- Configure package permissions so only this repository’s trusted workflow can publish/delete package versions. Do not give unrelated repositories inherited administration.

## Autonomous dependency policy

The owner explicitly selected full unattended maintenance. Dependabot owns only GitHub Actions pins; Renovate owns all other supported dependency managers and the custom BlueBuild CLI/Trivy version references. Renovate disables its GitHub Actions manager, so the bots never race on one dependency.

Both bots request GitHub native auto-merge; GitHub completes a merge only after the protected `policy`, `image`, and `dependency-review` checks pass. They open/rebase/merge PRs rather than directly pushing `main`; failures, upstream package incompatibilities, and unresolved checks remain fail-closed. Install the free Renovate GitHub App for this repository and keep its scope restricted to this repository. See [`AUTONOMOUS-MAINTENANCE.md`](AUTONOMOUS-MAINTENANCE.md).
