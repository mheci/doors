## What changed and why

<!-- Describe behavior and trust-boundary impact, not just files changed. -->

## Trust / release impact

- [ ] No signing key, token, generated Herdr binary, or credential is committed.
- [ ] New repository/key/artifact source is documented in `docs/TRUST-MODEL.md` and has a verification path.
- [ ] A workflow, build-chain, key, repository, or major-version change is marked for manual review (never Renovate auto-merge).
- [ ] Affected physical validation cases in `docs/TEST-PLAN.md` are identified.

## Required checks

- [ ] `./scripts/validate-repository.sh`
- [ ] CI policy job and one-image build pass.
- [ ] README/docs updated where user-visible behavior changed.
