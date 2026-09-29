#!/bin/sh
# OpenVIBES installer (https://openvibes-project.github.io/install.sh).
#   curl -fsSL https://openvibes-project.github.io/install.sh | sudo sh
#       adds the signed OpenVIBES package repository, installs the platform's
#       administration tool and opens its Setup.
#   … | sudo sh -s -- --agent --platform HOST[:PORT] --token TOKEN --ca-sha256 FP
#       installs the agent and enrolls it with that platform, trusting the
#       platform's CA only if its SHA-256 fingerprint is FP.
# Safer: download it, read it, then run: sudo sh install.sh [ARGS].
# Fedora 44 on x86_64 only. Stops at the first failure and says what it did.
set -eu

# The OpenVIBES package key (gpg --show-keys openvibes.gpg).
KEY_FINGERPRINT=710AD8AFB7AFE6E864C0CDC4E134BAF37786DA36
SITE=https://openvibes-project.github.io
# Test hooks (the installer's own container test); sudo drops them from a
# user's environment unless passed explicitly.
KEY_FINGERPRINT=${OPENVIBES_KEY_FINGERPRINT:-$KEY_FINGERPRINT}
SITE=${OPENVIBES_SITE:-$SITE}
AGENT_DIR=/etc/openvibes-agent
done_so_far="nothing changed"

die() {
    printf 'openvibes install: %s (%s)\n' "$1" "$done_so_far" >&2
    exit 1
}
say() { printf 'openvibes install: %s\n' "$1"; }

usage() {
    cat >&2 <<'EOF'
usage: install.sh                          install the platform's administration tool
       install.sh --agent --platform HOST[:PORT] --token TOKEN --ca-sha256 FP
EOF
    exit 2
}

mode=platform platform='' token='' fp=''
while [ $# -gt 0 ]; do
    case $1 in
        --agent) mode=agent ;;
        --platform) [ $# -ge 2 ] || usage; platform=$2; shift ;;
        --token) [ $# -ge 2 ] || usage; token=$2; shift ;;
        --ca-sha256) [ $# -ge 2 ] || usage; fp=$2; shift ;;
        -h|--help) usage ;;
        *) usage ;;
    esac
    shift
done

[ "$(id -u)" = 0 ] || die "run it as root (sudo sh install.sh …)"
[ "$KEY_FINGERPRINT" != unset ] || die "this copy of the installer has no package key fingerprint"
# shellcheck source=/dev/null
os_id=$(. /etc/os-release && printf %s "$ID")
# shellcheck source=/dev/null
os_version=$(. /etc/os-release && printf %s "${VERSION_ID:-}")
[ "$os_id" = fedora ] && [ "$os_version" = 44 ] && [ "$(uname -m)" = x86_64 ] ||
    die "OpenVIBES packages are for Fedora 44 on x86_64 (this is $os_id $os_version $(uname -m))"

if [ "$mode" = agent ]; then
    [ -n "$platform" ] && [ -n "$token" ] && [ -n "$fp" ] || usage
    host=${platform%:*}
    port=18423
    [ "$host" = "$platform" ] || port=${platform##*:}
    case $host in
        ''|*[!A-Za-z0-9.-]*|-*|*.) die "--platform: $host is not a DNS name or IPv4 address" ;;
    esac
    case $port in
        ''|*[!0-9]*) die "--platform: $port is not a port" ;;
    esac
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || die "--platform: $port is not a port"
    case $token in
        *[!A-Za-z0-9_-]*) die "--token is not an enrollment token" ;;
    esac
    [ "${#token}" = 43 ] || die "--token is not an enrollment token"
    fp=$(printf %s "$fp" | tr -d : | tr 'A-F' 'a-f')
    case $fp in
        *[!0-9a-f]*) die "--ca-sha256 is not a SHA-256 fingerprint" ;;
    esac
    [ "${#fp}" = 64 ] || die "--ca-sha256 is not a SHA-256 fingerprint"
    if [ -f "$AGENT_DIR/agent.toml" ] && ! grep -q '^platform_url = "https://platform.example.com"' "$AGENT_DIR/agent.toml"; then
        die "an agent is already configured in $AGENT_DIR/agent.toml; to enroll it elsewhere, see docs/components/packaging.md in openvibes-agent"
    fi
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# gpg checks the package key; minimal images may not have it (Fedora's
# own repositories provide it).
command -v gpg >/dev/null 2>&1 || dnf install -y -q gnupg2 >/dev/null || die "could not install gnupg2"

# The repository and its key.
curl -fsSL "$SITE/openvibes.gpg" -o "$tmp/openvibes.gpg" || die "could not download $SITE/openvibes.gpg"
got=$(gpg --batch --show-keys --with-colons "$tmp/openvibes.gpg" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
[ "$got" = "$KEY_FINGERPRINT" ] || die "the package key's fingerprint is ${got:-unreadable}, expected $KEY_FINGERPRINT"
cat > "$tmp/openvibes.repo" <<EOF
[openvibes]
name=OpenVIBES
baseurl=$SITE/rpm/fedora/\$releasever/\$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$SITE/openvibes.gpg
EOF
if [ -f /etc/yum.repos.d/openvibes.repo ]; then
    cmp -s "$tmp/openvibes.repo" /etc/yum.repos.d/openvibes.repo ||
        die "/etc/yum.repos.d/openvibes.repo differs from this installer's; check or remove it"
else
    install -m 0644 "$tmp/openvibes.repo" /etc/yum.repos.d/openvibes.repo
fi
rpm --import "$tmp/openvibes.gpg"
# dnf keeps a repository index for up to 48 h; one cached before a release
# does not list the new packages.
dnf makecache -y -q --refresh --repo openvibes >/dev/null || die "could not load the OpenVIBES repository index"
done_so_far="repository added"

if [ "$mode" = platform ]; then
    dnf install -y openvibes-admin || die "dnf could not install openvibes-admin"
    done_so_far="openvibes-admin installed"
    user=${SUDO_USER:-}
    if [ -n "$user" ] && [ "$user" != root ] && (: </dev/tty) 2>/dev/null; then
        say "opening the administration TUI (Setup) as $user"
        home=$(getent passwd "$user" | cut -d: -f6)
        rm -rf "$tmp"   # exec below replaces this shell: the EXIT trap will not run
        exec runuser -u "$user" -- env HOME="$home" USER="$user" /usr/bin/openvibes-admin </dev/tty >/dev/tty 2>&1
    fi
    say "installed. Next, as your own user: openvibes-admin (the Setup screen),"
    say "or as root: openvibes-admin setup --quick --components ingest,console,distribution,vulns,rules,agent --hostname NAME --root-key-out /root/openvibes-root-ca.key"
    exit 0
fi

# Agent: the platform's CA, by fingerprint, then the server against it.
url=https://$host:$port
curl -fsS --insecure --max-time 10 "$url/v1/ca" -o "$tmp/ca.pem" ||
    die "could not fetch the platform's CA from $url/v1/ca (is Setup finished there?)"
ca=$(sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' "$tmp/ca.pem" |
    grep -v -- ----- | tr -d '\r\n' | base64 -d 2>/dev/null | sha256sum | cut -d' ' -f1)
[ "$ca" = "$fp" ] || die "the platform's CA has fingerprint $ca, not the expected $fp"
curl -fsS --cacert "$tmp/ca.pem" --max-time 10 "$url/v1/ca" -o /dev/null ||
    die "the server at $url does not hold a certificate from that CA"

dnf install -y openvibes-agent || die "dnf could not install openvibes-agent"
done_so_far="openvibes-agent installed, not configured"
platform_url=https://$host
[ "$port" = 18423 ] || platform_url=$url
cat > "$tmp/agent.toml" <<EOF
# Written by the OpenVIBES installer.
state_dir = "/var/lib/openvibes-agent"
platform_url = "$platform_url"
platform_ca_file = "$AGENT_DIR/platform-ca.crt"
enrollment_token_file = "$AGENT_DIR/token"
EOF
(umask 077 && printf '%s\n' "$token" > "$tmp/token")
install -m 0644 "$tmp/ca.pem" "$AGENT_DIR/platform-ca.crt"
install -o openvibes_agent -g openvibes_agent -m 0600 "$tmp/token" "$AGENT_DIR/token"
install -o root -g openvibes_agent -m 0640 "$tmp/agent.toml" "$AGENT_DIR/agent.toml"
done_so_far="openvibes-agent installed and configured"
start=$(date '+%Y-%m-%d %H:%M:%S')
systemctl enable --now openvibes-agent || die "the agent did not start (journalctl -u openvibes-agent)"
i=0
while [ $i -lt 60 ]; do
    line=$(journalctl -u openvibes-agent --since "$start" -o cat 2>/dev/null | grep -m1 '^openvibes-agent: enrolled as ' || true)
    if [ -n "$line" ]; then
        say "${line#openvibes-agent: }"
        exit 0
    fi
    i=$((i + 1))
    sleep 1
done
die "the agent has not enrolled after 60 seconds; see journalctl -u openvibes-agent"
