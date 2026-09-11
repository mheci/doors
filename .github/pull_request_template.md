## What

<!-- What does this PR change and why? -->

## Checklist

- [ ] `recipes/*.yml` validate against the BlueBuild schema (`just validate` or CI build)
- [ ] New/changed scripts pass `bash -n` and `shellcheck` where available
- [ ] Docs (`docs/`, `README.md`) updated if behaviour changed
- [ ] New files follow the existing directory conventions under `files/`
- [ ] Signing / cosign key not committed (only `cosign.pub`)

## Image matrix affected

<!-- e.g. all six, or only -nvidia variants -->
