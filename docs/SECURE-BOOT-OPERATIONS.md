# Secure Boot MOK operations

## Trust boundary

**Release safeguard:** publish or enroll only a production identity whose private PEM is already stored in the protected environment and whose matching public DER/fingerprint arrives through a normal protected PR. An absent or mismatched secret makes the signer fail closed; never use a development fixture.

Doors uses one RSA MOK identity for released images. Its public X.509 DER and a
lowercase SHA-256 fingerprint manifest live at:

- `/usr/share/doors/secureboot/doors-mok.der`
- `/usr/share/doors/secureboot/doors-mok.fingerprint`

Only the matching PEM private key belongs in the protected GitHub Actions
environment secret `DOORS_MOK_SIGNING_KEY` on `ghcr-publish`. It must never be
committed, attached to an artifact, copied into an image, printed, or placed in
a repository/environment scope available to pull requests.

The late BlueBuild module receives the secret as a BuildKit file mount at
`/run/secrets/doors-mok.key`. The signer checks that its public key matches the
tracked DER before signing any payload. Trusted stable and trusted daily-staging
publication actions are the only workflow steps permitted to supply the
production secret. Candidate compositions generate their own disposable key
pair and alter only their runner checkout.

## One-time production activation

Perform this only while authorized to update the protected GitHub environment.
Use a clean, access-controlled temporary directory or RAM-backed filesystem;
do not run the commands in a repository directory.

1. Generate an RSA-4096 end-entity code-signing MOK PEM and DER with subject
   `CN=Doors Secure Boot MOK`, `CA:FALSE`, critical digital-signature key usage,
   and Code Signing extended key usage:

   ```bash
   umask 077
   workdir=/secure/tmp/doors-mok-rotation
   install -d -m 0700 "$workdir"
   openssl req -x509 -newkey rsa:4096 -sha256 -nodes \
     -keyout "$workdir/doors-mok.key" \
     -out "$workdir/doors-mok.pem" \
     -days 3650 \
     -subj '/CN=Doors Secure Boot MOK/' \
     -addext 'basicConstraints=critical,CA:FALSE' \
     -addext 'keyUsage=critical,digitalSignature' \
     -addext 'extendedKeyUsage=codeSigning' \
     -addext 'subjectKeyIdentifier=hash' \
     -addext 'authorityKeyIdentifier=keyid'
   openssl x509 -in "$workdir/doors-mok.pem" -outform DER \
     -out "$workdir/doors-mok.der"
   openssl x509 -inform DER -in "$workdir/doors-mok.der" -noout \
     -fingerprint -sha256
   ```

2. Confirm the private key and DER have the same public-key hash; the two
   commands below must print the same digest. Record the DER's SHA-256
   fingerprint as well:

   ```bash
   openssl pkey -in "$workdir/doors-mok.key" -pubout -outform DER | sha256sum
   openssl x509 -inform DER -in "$workdir/doors-mok.der" -pubkey -noout \
     | openssl pkey -pubin -outform DER | sha256sum
   openssl x509 -inform DER -in "$workdir/doors-mok.der" -noout \
     -fingerprint -sha256
   ```
3. Set the PEM **only** as the `DOORS_MOK_SIGNING_KEY` environment secret of
   `ghcr-publish` (for example, `gh secret set DOORS_MOK_SIGNING_KEY --env
   ghcr-publish < "$workdir/doors-mok.key"`). Do not use a repository
   secret, an organization secret, workflow output, or a plaintext variable.
4. In a normal protected pull request, replace only the tracked DER and
   `doors-mok.fingerprint` with the matching public values. Run repository
   validation and review the certificate subject, extensions, and fingerprint.
5. Securely remove all temporary PEM/key material. Verify the protected secret
   exists without printing it, merge through the required checks, and inspect
   the first trusted publish for the signer count and absence of secret output.

The private key must be available in protected GitHub storage before a PR with
its matching public certificate reaches `main`; otherwise trusted publication
fails closed rather than shipping unsigned kernel payloads.

## Target enrollment and verification

A target owner must compare the release certificate identity before enrollment:

```bash
doors-secureboot fingerprint
sudo doors-secureboot enroll
```

`mokutil` asks for a one-time password. After reboot, the physical owner must
select **Enroll MOK**, approve the request, and enter that password in
MokManager. If a MOK-trust prompt appears, approve it there as well. This
firmware-owner approval is intentionally not automatable by CI, SSH, or the
image build.

After the next normal boot:

```bash
doors-secureboot status
doors-secureboot verify
```

The latter verifies current `vmlinuz*`/EFI kernel payloads with `sbverify` and
all supported compressed or uncompressed kernel modules through `modinfo`.
`ujust doors-secureboot-enroll` and `ujust doors-secureboot-status` are
convenience aliases.

## Rotation and incident response

A lost, suspected-exposed, or expired MOK requires a new identity. Follow the
same protected PR/secret sequence, enroll the new public DER on targets, verify
a release signed by it, then remove the old MOK through the target's documented
MokManager/mokutil removal procedure only after all deployments are migrated.
Never reuse a development fixture or try to remote-approve a MOK change.
