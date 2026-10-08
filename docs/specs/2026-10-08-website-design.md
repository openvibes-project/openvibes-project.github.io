# Project website: a landing page for newcomers

Date: 2026-10-08. Design session with the user; mockups in the visual
companion (directions, style, full page v1 and v2).

## 1. Goal

`https://openvibes-project.github.io/` today is a 29-line "OpenVIBES
packages" page: install commands and the package key. It becomes the
project's front door: a newcomer (homelab, small business, security
enthusiast) understands what OpenVIBES is and why it is different, sees it
(real screenshots, the live demo), and knows how to start. The package
repository and key details move to their own small page.

Success: a visitor can, from the first screen, open the live demo or jump to
the install steps; every claim on the page is true of the current release;
the page is fast, readable at phone width, and follows the visitor's
light/dark setting.

## 2. Decisions (user, 2026-10-08)

- **Direction A**: a landing page for newcomers; package/key details on a
  separate page (not direction B, a styled reference page, nor C, both on
  one page).
- **Featured capabilities**, each with its own block and screenshot:
  vulnerabilities, compliance rules, threat alarms, the local AI assistant.
- **Stage**: a clear "Early release" badge and a plain "Runs on" list, plus
  a "What's next" roadmap.
- **Style**: dark, like the console (its colours and a subtle blue glow),
  and following the visitor's light/dark setting.
- **Top of the page**: two buttons, "Try the live demo" (opens the demo
  console) and "Get started" (jumps down to the install steps on the same
  page). No install command in the hero (v1 placed it beside the demo
  button and the user read the button as pointing at it).
- **Roadmap** includes "Platform on AlmaLinux and Rocky Linux" (user).

## 3. Pages

### 3.1 `index.html`, the landing page

Top to bottom (full-page mockup v2):

1. **Navigation**: wordmark; Features, Live demo, Get started, Docs, GitHub.
2. **Hero**: badge "Early release 0.2 · free and open source (MIT)" (the current release, updated when one is cut);
   headline "See what runs on your machines, and what threatens them.";
   one-sentence pitch ("A light, self-hosted security platform for homelabs
   and small businesses: vulnerabilities, compliance, threat alarms and a
   local AI assistant, in one fast console."); buttons **Try the live demo**
   (primary) and **Get started ↓** (secondary, `#get-started`); a short line
   "Free · self-hosted · platform on Fedora 44"; the dashboard screenshot in
   a browser frame.
3. **What it does**: "Four things, done properly", four rows alternating
   text and screenshot:
   - *Know what's vulnerable*: installed software matched against the
     distributions' advisories, known-exploited first; software, ports and
     services per host.
   - *Check your baseline*: signed compliance rules on every host, baseline
     included, your own rules signed on your platform.
   - *Hear about threats in seconds*: every program start watched (eBPF,
     kernel audit as fallback); the alarm, why it fired and the process tree
     in the console seconds later; quiet by default, suppressions, triage,
     cases, audit trail.
   - *Ask in plain words*: the optional assistant runs on your own platform;
     no data leaves your network.
4. **Why OpenVIBES**: "Built for people who are tired of heavy security
   tools", six tiles from the design principles (workspace `decisions.md`):
   interface first, light agent, quiet by default, yours to shape, your data
   stays yours, no licence locks.
5. **Where it stands**: "An early release, moving fast".
   - *Runs on today*: platform Fedora 44 (x86_64); agents Fedora, other
     systems working with packages coming; the platform's memory need.
   - *What's next*: Debian, Ubuntu and Arch agent packages; fully offline
     agent install from the console; platform on AlmaLinux and Rocky Linux;
     a friendlier Setup and first run; Windows agent.
6. **Get started** (`id="get-started"`): three numbered steps: install the
   platform (the one-line command, copyable), run Setup, add hosts from the
   console (Enrollment → Copy CLI install). Links: the quick-setup guide;
   "read the script first": download `install.sh`, then `sudo sh install.sh`;
   "no output at all means the download failed".
7. **Footer**: MIT licence, no telemetry; GitHub, Docs, Packages and signing
   key, Security policy.

### 3.2 `packages.html`, packages and signing key

Today's reference content, in the same style: the repository (Fedora 44,
`openvibes.repo`), the key `openvibes.gpg` with its fingerprint
`710A D8AF B7AF E6E8 64C0 CDC4 E134 BAF3 7786 DA36` and how to check it,
`install.sh` (download, read, run), the releases list (`releases.txt`),
"add an agent" pointing to the console's Enrollment page and to
`openvibes-admin agent command`.

## 4. Look

- Colours from the console's tokens (`crates/openvibes-console/web/src/styles/tokens.css`
  in openvibes-platform): accent `#0a6ea5`, dark canvas; the hero's glow is
  a radial gradient. Light variant under `prefers-color-scheme: light`,
  dark otherwise (dark is the default when the visitor states nothing).
- The wordmark from openvibes-platform `docs/brand/` (dark and light SVGs).
- System font stack; no web fonts.
- Layout: max width about 1060 px; feature rows stack (text above the
  screenshot) below about 760 px; usable at 360 px wide, no horizontal
  scrolling.

## 5. How it is built

- Hand-written static files, no build step and no JavaScript: `index.html`,
  `packages.html`, `site.css`, and `assets/` (wordmark SVGs, screenshots).
  The "Get started" button is a plain `#get-started` link; the copy of the
  install command is a selectable `<pre>`.
- `scripts/build-repo.sh` copies the new files into the site beside
  `install.sh` and the repository (today it copies only `index.html`).
- **Screenshots**: taken from the live demo
  (`https://openvibes-project.github.io/openvibes-platform/`, synthetic data
  only) at 1440×900, dark theme: dashboard, vulnerabilities, compliance, an
  alarm with its detail, the assistant answering. Saved as WebP (PNG
  fallback not needed: every current browser reads WebP), each with real
  alt text. Total images under 1 MB: the site is already over GitHub Pages'
  1 GB soft limit because of the model packages (`status.md` follow-up), so
  the page adds as little as possible.
- The version in the badge is written by hand when a release is cut
  (a line in the release checklist), not fetched at run time.

## 6. Facts to verify before publishing

Every claim must be true of the current release; each is checked against
its source when the page is written:

| Claim | Source to check |
|---|---|
| Advisory sources (Fedora, Debian, Ubuntu, Rocky) | openvibes-vulns docs (`docs/components/openvibes-vulns.md`) |
| Compliance examples ("SSH root login", others) | openvibes-rules baseline rule list |
| "Software, ports and services per host" | console Hosts page tabs |
| Alarms: eBPF with audit fallback, "seconds" | agent eBPF watcher spec, lab result 2026-10-08 (2 s) |
| Assistant: local, optional, no data leaves | openvibes-llm docs |
| Platform memory need | openvibes-platform `docs/sizing.md` |
| Agents on other systems "working" | lab `agent-generic.sh` (no packages yet) |
| Light agent wording | agent footprint budget; no number unless measured for this release |

A claim that cannot be backed is cut or softened, not kept.

## 7. Testing

- `tests/test-build-repo.sh` checks the built site holds `index.html`,
  `packages.html`, `site.css` and every file `assets/` references.
- A link check over both pages: every local link and asset exists; the demo
  and GitHub links answer.
- Looked at in Firefox at desktop and phone width, light and dark.
- An accessibility check (contrast, alt text, heading order, keyboard
  focus visible).

## 8. Out of scope

A separate Get started page (later, when per-distribution packages and the
offline install give it more to say), a blog or news, a docs site
(the docs stay in the repositories), analytics of any kind (no telemetry).
