### Change

<!-- One or two lines: what changes in the composed image or the pipeline. -->

### Verification

- [ ] `shellcheck` is clean for every changed module under `modules/` and every image payload script.
- [ ] All three desktop recipes (`doors`, `doors-cosmic`, `doors-kinoite`) compose and pass the boot gate in CI.
- [ ] No new repository, signing key, or third-party artifact is introduced without a pinned digest or signature check.
- [ ] New functionality is expressed through a BlueBuild module where one exists, or a custom module under `modules/`.
- [ ] No secret, private key, or token is added to the repository, an image layer, or a workflow log.
