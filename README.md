# openvibes-project.github.io

The OpenVIBES package repository and installer, published at
<https://openvibes-project.github.io/>:

- `install.sh`: `sudo sh -c "$(curl -fsSL https://openvibes-project.github.io/install.sh)"`
  installs the platform's administration tool and opens its Setup;
  `curl -fsSL …/install.sh | sudo sh -s -- --agent --platform HOST --token TOKEN --ca-sha256 FP`
  installs and enrolls an agent. The platform on Fedora 44; agents on
  Fedora 44, AlmaLinux and Rocky 9+, Debian 12+, Ubuntu 22.04+ and Arch;
  x86_64.
- `rpm/fedora/44/x86_64/`: every released RPM of
  [openvibes-platform](https://github.com/openvibes-project/openvibes-platform),
  [openvibes-agent](https://github.com/openvibes-project/openvibes-agent) and
  [openvibes-rules](https://github.com/openvibes-project/openvibes-rules),
  with `repodata/repomd.xml.asc`. The assistant's model parts
  (`openvibes-llm-model-part*`) are not published: the model comes from its
  publisher.
- `deb/`: a flat apt repository of the agent's .deb packages (`InRelease`
  clear-signed, valid 30 days).
- `arch/x86_64/`: a pacman repository of the agent's Arch packages
  (`openvibes.db.sig`).
- `packages.html`: the repositories, the key, and the platform's offline
  kit.
- `openvibes.gpg`: the package key, fingerprint
  `710AD8AFB7AFE6E864C0CDC4E134BAF37786DA36` (expires 2029-09-26), also
  written into `install.sh`. Check: `gpg --show-keys openvibes.gpg`.

No package is ever committed here. A release in openvibes-platform,
openvibes-agent or openvibes-rules signs its packages (RPMs inside; .deb and
Arch packages with a detached `.sig`) and checks them. Every 30
minutes `.github/workflows/publish.yml` compares the release list
(`scripts/releases.sh`) with the deployed `releases.txt`; when it changed
(or on a push or a manual run: `gh workflow run publish.yml`), it collects
every release
(`scripts/collect.sh`), refuses to publish if any package fails the key
check, indexes and signs the metadata of all three repositories
(`scripts/build-repo.sh`), and deploys the site. It also rebuilds when the
deployed apt index has less than 14 days of validity left. `tests/test-build-repo.sh` tests that (CI). No token is involved.
GitHub disables schedules after 60 days without a commit here; if that
happens, re-enable the workflow under Actions.

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
