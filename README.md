<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/wordmark-dark.svg">
    <img src="assets/wordmark-light.svg" alt="OpenVIBES" width="520">
  </picture>
</p>

<h3 align="center">OpenVIBES website and packages</h3>

<p align="center">
  The website of <a href="https://github.com/openvibes-project">OpenVIBES</a>, its installer and its signed package
  repositories, published at <a href="https://openvibes-project.github.io/">openvibes-project.github.io</a>.
</p>

## What's here

- **The website:** `index.html` and `packages.html`.
- **The installer, `install.sh`.** For a platform on Fedora 44:

  ```sh
  sudo sh -c "$(curl -fsSL https://openvibes-project.github.io/install.sh)"
  ```

  It also installs and enrolls agents; the platform console gives you that
  command with everything filled in.
- **Signed package repositories** for every release of the platform, the
  agent and the rules: RPM (`rpm/`), apt (`deb/`) and pacman (`arch/`).
- **The package key**, `openvibes.gpg`, fingerprint
  `710AD8AFB7AFE6E864C0CDC4E134BAF37786DA36`. Check it with
  `gpg --show-keys openvibes.gpg`.

No package is committed here. A workflow collects the signed packages from
each release, checks them against the key, and publishes the site.
How that works, and how to replace the key:
[`docs/publishing.md`](docs/publishing.md).

## Contributing

Issues and pull requests are welcome; see [`CONTRIBUTING.md`](CONTRIBUTING.md).
Security problems: please use private vulnerability reporting, not a public
issue.

**AI disclosure:** OpenVIBES is built with the help of AI coding tools
(Claude Code and Codex). Every change goes through a pull request and the
full CI before it is merged.

Licensed under the [Apache License 2.0](LICENSE).
