# openvibes-project.github.io

The OpenVIBES package repository and installer, published at
<https://openvibes-project.github.io/>:

- `install.sh`: `curl -fsSL https://openvibes-project.github.io/install.sh | sudo sh`
  installs the platform's administration tool and opens its Setup;
  `… | sudo sh -s -- --agent --platform HOST --token TOKEN --ca-sha256 FP`
  installs and enrolls an agent. Fedora 44 on x86_64.
- `rpm/fedora/44/x86_64/`: every released package of
  [openvibes-platform](https://github.com/openvibes-project/openvibes-platform)
  and [openvibes-agent](https://github.com/openvibes-project/openvibes-agent),
  with `repodata/repomd.xml.asc`.
- `openvibes.gpg`: the package key, fingerprint
  `710AD8AFB7AFE6E864C0CDC4E134BAF37786DA36` (expires 2029-09-26), also
  written into `install.sh`. Check: `gpg --show-keys openvibes.gpg`.

No package is ever committed here. A release in openvibes-platform,
openvibes-agent or openvibes-rules signs its RPMs, checks them, and
dispatches `release-published`;
`.github/workflows/publish.yml` then collects every release
(`scripts/collect.sh`), refuses to publish if any package fails the key
check, indexes and signs the metadata (`scripts/build-repo.sh`), and deploys
the site. `tests/test-build-repo.sh` tests that (CI).

## Replacing the key

1. Generate the new key and add its public half next to the old one in
   `openvibes.gpg` and in both code repositories'
   `packaging/rpm/openvibes-packages.gpg`.
2. Replace the organisation secrets `RPM_SIGNING_KEY` and
   `RPM_SIGNING_PASSPHRASE`; make a new release of each code repository so
   every published package is signed by the new key (or re-sign the old
   releases' assets).
3. Update `KEY_FINGERPRINT` in `install.sh` and the fingerprint here and in
   `index.html`; publish.
4. Remove the old public key; publish. Revoke it if it was compromised
   (the revocation certificate is kept offline with the secret key).

Spec: openvibes-platform `docs/specs/2026-09-27-releases-design.md`.
