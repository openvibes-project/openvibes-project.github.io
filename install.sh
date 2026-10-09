#!/bin/sh
# OpenVIBES installer (https://openvibes-project.github.io/install.sh).
#   sudo sh -c "$(curl -fsSL https://openvibes-project.github.io/install.sh)"
#       adds the signed OpenVIBES package repository, installs the platform's
#       administration tool and opens its Setup (piped into sudo sh, it
#       prints how to open Setup instead: a pipe is not a terminal).
#   curl -fsSL https://openvibes-project.github.io/install.sh | sudo sh -s -- --agent --platform HOST[:PORT] --token TOKEN --ca-sha256 FP [--rules SET,ISSUER,KEY [--alarm-rules SET,ISSUER,KEY] [--distribution-port PORT]]
#       installs the agent and enrolls it with that platform, trusting the
#       platform's CA only if its SHA-256 fingerprint is FP.
# Safer: download it, read it, then run: sudo sh install.sh [ARGS].
# The platform: Fedora 44. Agents: Fedora 44, AlmaLinux and Rocky 9+,
# Debian 12+, Ubuntu 22.04+ and Arch; x86_64 only. Stops at the first
# failure and says what it did.
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
# canonical_ca IN OUT: IN must hold exactly one PEM block, a CERTIFICATE; OUT is rebuilt
# from that block's bytes alone, and its SHA-256 (of the DER) is printed. Whatever else
# IN holds never reaches the trusted file: curl and OpenSSL also read other PEM forms
# (e.g. TRUSTED CERTIFICATE), so checking one block and trusting the whole file would
# let a man in the middle add a CA of their own next to the real one.
canonical_ca() {
    if ! { [ "$(grep -c -- '-----BEGIN ' "$1")" = 1 ] && [ "$(grep -c -- '-----END ' "$1")" = 1 ] &&
        grep -qx -- '-----BEGIN CERTIFICATE-----' "$1" && grep -qx -- '-----END CERTIFICATE-----' "$1"; }; then
        die "the platform's CA answer is not exactly one certificate"
    fi
    sed -n '/^-----BEGIN CERTIFICATE-----$/,/^-----END CERTIFICATE-----$/p' "$1" |
        grep -v -- '-----' | tr -d '\r\n' | base64 -d > "$2.der" 2>/dev/null || die "the platform's CA is not valid base64"
    [ -s "$2.der" ] || die "the platform's CA is empty"
    { echo '-----BEGIN CERTIFICATE-----'; base64 -w 64 "$2.der"; echo '-----END CERTIFICATE-----'; } > "$2"
    sha256sum "$2.der" | cut -d' ' -f1
    rm -f "$2.der"
}
# install_package NAME: dnf installs it, its output kept in a log that is
# shown only if it fails. dnf -q still prints every scriptlet's output
# (">>> Running …"), which buried the next step (install walkthrough,
# 2026-10-08).
install_package() {
    say "installing $1 (a minute or two)"
    pkg=$1
    case $family in
        rpm) set -- dnf install -y "$pkg" ;;
        deb) set -- env DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" ;;
        # ponytail: -Sy without -u; the agent needs only glibc, libgcc and
        # systemd, already current on a maintained host.
        arch) set -- pacman -Sy --noconfirm --needed "$pkg" ;;
    esac
    "$@" > "$tmp/install.log" 2>&1 || {
        tail -n 25 "$tmp/install.log" >&2
        die "the package manager could not install $pkg"
    }
}
# installed NAME: the package is installed, by this system's package manager.
installed() {
    case $family in
        rpm) rpm -q --quiet "$1" ;;
        deb) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
        arch) pacman -Q "$1" >/dev/null 2>&1 ;;
    esac
}
# package_files NAME: the files the installed package owns.
package_files() {
    case $family in
        rpm) rpm -ql "$1" ;;
        deb) dpkg-query -L "$1" ;;
        arch) pacman -Qlq "$1" ;;
    esac
}
# put_file NEW DEST: install NEW at DEST, or keep DEST if it is the same;
# a different DEST is someone's edit, not ours to overwrite.
put_file() {
    if [ -f "$2" ]; then
        cmp -s "$1" "$2" || die "$2 differs from this installer's; check or remove it"
    else
        install -D -m 0644 "$1" "$2"
    fi
}

usage() {
    cat >&2 <<'EOF'
usage: install.sh                          install the platform's administration tool
       install.sh --agent --platform HOST[:PORT] --token TOKEN --ca-sha256 FP [--rules SET,ISSUER,KEY [--alarm-rules SET,ISSUER,KEY] [--distribution-port PORT]]
EOF
    exit 2
}

# check_key FILE: FILE holds exactly one key, the pinned one. rpm --import and
# apt's signed-by trust every key in the file they are given, so a second key
# next to the real one must not get through.
check_key() {
    keys=$(gpg --batch --show-keys --with-colons "$1" 2>/dev/null | awk -F: '$1 == "pub" { n++ } $1 == "fpr" && !f { f = $10 } END { print n + 0, f }')
    [ "${keys%% *}" -le 1 ] || die "the package key file holds ${keys%% *} keys; only $KEY_FINGERPRINT is expected"
    got=${keys#* }
    [ "$got" = "$KEY_FINGERPRINT" ] || die "the package key's fingerprint is ${got:-unreadable}, expected $KEY_FINGERPRINT"
}
# pinned_key IN OUT: IN passes check_key; OUT is gpg's own export of the pinned
# key alone. rpm, apt, pacman and dnf are given OUT, never IN: they parse key
# files themselves, and anything they read that gpg did not would be trusted.
pinned_key() {
    check_key "$1"
    pk_home=$(mktemp -d)
    GNUPGHOME=$pk_home gpg --batch -q --import "$1" 2>/dev/null || :
    GNUPGHOME=$pk_home gpg --batch -q --armor --export-options export-minimal --export "$KEY_FINGERPRINT" > "$2" 2>/dev/null || :
    gpgconf --homedir "$pk_home" --kill all 2>/dev/null || :
    rm -rf "$pk_home"
    [ -s "$2" ] || die "could not export the package key $KEY_FINGERPRINT"
    check_key "$2"
}
# Test hooks (tests/test-install-ca.sh, tests/test-install-key.sh): one check alone.
if [ "${1:-}" = --canonical-ca ]; then [ $# = 3 ] || usage; canonical_ca "$2" "$3"; exit 0; fi
if [ "${1:-}" = --pinned-key ]; then [ $# = 3 ] || usage; pinned_key "$2" "$3"; exit 0; fi

mode=platform platform='' token='' fp='' rules='' alarm_rules='' dport=''
while [ $# -gt 0 ]; do
    case $1 in
        --agent) mode=agent ;;
        --platform) [ $# -ge 2 ] || usage; platform=$2; shift ;;
        --token) [ $# -ge 2 ] || usage; token=$2; shift ;;
        --ca-sha256) [ $# -ge 2 ] || usage; fp=$2; shift ;;
        --rules) [ $# -ge 2 ] || usage; rules=$2; shift ;;
        --alarm-rules) [ $# -ge 2 ] || usage; alarm_rules=$2; shift ;;
        --distribution-port) [ $# -ge 2 ] || usage; dport=$2; shift ;;
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
major=${os_version%%.*} family=''
case $os_id in
    fedora) [ "$os_version" = 44 ] && family=rpm ;;
    almalinux|rocky) [ "${major:-0}" -ge 9 ] 2>/dev/null && family=rpm ;;
    debian) [ "${major:-0}" -ge 12 ] 2>/dev/null && family=deb ;;
    ubuntu) [ "${major:-0}" -ge 22 ] 2>/dev/null && family=deb ;;
    arch) family=arch ;;
esac
[ "$(uname -m)" = x86_64 ] && [ -n "$family" ] ||
    die "OpenVIBES agent packages are for Fedora 44, AlmaLinux and Rocky 9+, Debian 12+, Ubuntu 22.04+ and Arch on x86_64 (this is $os_id $os_version $(uname -m))"
[ "$mode" = agent ] || { [ "$os_id" = fedora ] && [ "$os_version" = 44 ]; } ||
    die "the OpenVIBES platform is for Fedora 44 on x86_64 (this is $os_id $os_version)"

if [ "$mode" = agent ]; then
    [ -n "$platform" ] && [ -n "$token" ] && [ -n "$fp" ] || usage
    # --rules SET,ISSUER,KEY: the rule set the platform publishes and the
    # key it trusts (from the same fingerprint-checked command line).
    # SET,ISSUER,KEY: SET and ISSUER are agent identifiers (1-128 of the
    # characters below), KEY a 43-character base64url public key.
    check_set() { # FLAG VALUE
        case $2 in *[!A-Za-z0-9.:_,-]*) die "$1: unexpected characters" ;; esac
        set_id=${2%%,*} rest=${2#*,}
        set_issuer=${rest%%,*} set_key=${rest#*,}
        { [ -n "$set_id" ] && [ -n "$set_issuer" ] && [ "$rest" != "$2" ] &&
            [ "${#set_id}" -le 128 ] && [ "${#set_issuer}" -le 128 ] &&
            [ "$set_key" != "$rest" ] && [ "${#set_key}" = 43 ] &&
            case $set_key in *[!A-Za-z0-9_-]*) false ;; *) true ;; esac; } ||
            die "$1: want SET,ISSUER,KEY (SET and ISSUER up to 128 characters, a 43-character base64url key)"
    }
    if [ -n "$rules" ]; then
        check_set --rules "$rules"
        rule_set=$set_id rule_issuer=$set_issuer rule_key=$set_key
    fi
    # --alarm-rules: the threat-alarm rule set (P14). It shares --rules'
    # distribution URL, and only a P14 agent gets it (checked after install).
    if [ -n "$alarm_rules" ]; then
        [ -n "$rules" ] || die "--alarm-rules needs --rules"
        check_set --alarm-rules "$alarm_rules"
        alarm_set=$set_id alarm_issuer=$set_issuer alarm_key=$set_key
        # Two rule sets with one id make the agent refuse its config.
        [ "$alarm_set" != "$rule_set" ] || die "--alarm-rules: the same rule set as --rules ($rule_set)"
    fi
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
    # The rules come from the distribution service, on 18424 unless the
    # platform chose another port.
    if [ -n "$dport" ]; then
        [ -n "$rules" ] || die "--distribution-port needs --rules"
        case $dport in
            *[!0-9]*|0*) die "--distribution-port: $dport is not a port" ;;
        esac
        [ "$dport" -ge 1 ] && [ "$dport" -le 65535 ] || die "--distribution-port: $dport is not a port"
    fi
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

# gpg checks the package key; minimal images may not have it (the
# system's own repositories provide it; Arch always has it).
if ! command -v gpg >/dev/null 2>&1; then
    case $family in
        rpm) dnf install -y -q gnupg2 >/dev/null ;;
        deb) { apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q gnupg; } >/dev/null ;;
        arch) false ;;
    esac || die "could not install gnupg"
fi

# The repository and its key.
curl -fsSL "$SITE/openvibes.gpg" -o "$tmp/openvibes.gpg" || die "could not download $SITE/openvibes.gpg"
pinned_key "$tmp/openvibes.gpg" "$tmp/pinned.asc"
case $family in
    rpm)
        # The agent RPM is the same file for every rpm system; EL's
        # $releasever would be 9 or 10.
        # ponytail: EL reads the Fedora 44 folder; give the agent its own rpm folder if the RPMs ever differ.
        # shellcheck disable=SC2016  # dnf expands $releasever
        release='$releasever'
        [ "$os_id" = fedora ] || release=44
        # gpgkey is the checked export on disk: with the website's URL, dnf
        # would fetch and trust the raw file itself.
        # Ours, always rewritten with the checked export (a renewed key must get through).
        install -D -m 0644 "$tmp/pinned.asc" /etc/pki/rpm-gpg/RPM-GPG-KEY-openvibes
        repo_file() { # GPGKEY OUT
            cat > "$2" <<EOF
[openvibes]
name=OpenVIBES
baseurl=$SITE/rpm/fedora/$release/\$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$1
EOF
        }
        repo_file file:///etc/pki/rpm-gpg/RPM-GPG-KEY-openvibes "$tmp/openvibes.repo"
        repo_file "$SITE/openvibes.gpg" "$tmp/openvibes.repo.old"
        # Installers before 2026-10-09 wrote gpgkey=$SITE/openvibes.gpg: that exact
        # file is ours to replace; any other edit is refused by put_file.
        if [ -f /etc/yum.repos.d/openvibes.repo ] && cmp -s "$tmp/openvibes.repo.old" /etc/yum.repos.d/openvibes.repo; then
            install -m 0644 "$tmp/openvibes.repo" /etc/yum.repos.d/openvibes.repo
        fi
        put_file "$tmp/openvibes.repo" /etc/yum.repos.d/openvibes.repo
        rpm --import "$tmp/pinned.asc"
        # dnf keeps a repository index for up to 48 h; one cached before a release
        # does not list the new packages.
        dnf makecache -y -q --refresh --repo openvibes >/dev/null || die "could not load the OpenVIBES repository index" ;;
    deb)
        # A flat repository; apt reads the armoured key from signed-by (apt 2.4+).
        install -D -m 0644 "$tmp/pinned.asc" /etc/apt/keyrings/openvibes.asc   # ours, always the checked export
        echo "deb [signed-by=/etc/apt/keyrings/openvibes.asc] $SITE/deb ./" > "$tmp/openvibes.list"
        put_file "$tmp/openvibes.list" /etc/apt/sources.list.d/openvibes.list
        apt-get update -q -o Dir::Etc::sourcelist=sources.list.d/openvibes.list \
            -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 >/dev/null ||
            die "could not load the OpenVIBES repository index" ;;
    arch)
        { pacman-key --add "$tmp/pinned.asc" && pacman-key --lsign-key "$KEY_FINGERPRINT"; } >/dev/null 2>&1 ||
            die "could not add the package key to pacman's keyring"
        # shellcheck disable=SC2016  # pacman expands $arch
        server='Server = '"$SITE"'/arch/$arch'
        if grep -q '^\[openvibes\]' /etc/pacman.conf; then
            grep -qxF "$server" /etc/pacman.conf ||
                die "/etc/pacman.conf has an [openvibes] section that differs from this installer's; check or remove it"
        else
            printf '\n[openvibes]\nSigLevel = Required DatabaseRequired\n%s\n' "$server" >> /etc/pacman.conf
        fi ;;
esac
done_so_far="repository added"

if [ "$mode" = platform ]; then
    install_package openvibes-admin
    done_so_far="openvibes-admin installed"
    user=${SUDO_USER:-}
    # Only when stdin is the terminal (sudo sh -c "$(curl ...)", the
    # documented command, or sudo sh install.sh). Under curl | sudo sh stdin
    # is the pipe, and sudo killed the TUI opened on /dev/tty two seconds in
    # (2026-09-29, sudo 1.9.17p2), so we print the next step instead.
    if [ -n "$user" ] && [ "$user" != root ] && [ -t 0 ]; then
        say "opening the administration TUI (Setup)"
        home=$(getent passwd "$user" | cut -d: -f6)
        rm -rf "$tmp"   # exec below replaces this shell: the EXIT trap will not run
        # As root (we run under sudo): Setup asks for no password (#92).
        # SUDO_USER and HOME stay the person's, so Setup adds them to
        # openvibes-operators and writes the root key into their home.
        exec env HOME="$home" SUDO_USER="$user" /usr/bin/openvibes-admin
    fi
    say "installed. Next: sudo openvibes-admin (the Setup screen),"
    say "or as root: openvibes-admin setup --quick --components ingest,console,distribution,vulns,rules,agent --hostname NAME --root-key-out /root/openvibes-root-ca.key"
    exit 0
fi

# Agent: the platform's CA, by fingerprint, then the server against it.
url=https://$host:$port
curl -fsS --insecure --max-time 10 "$url/v1/ca" -o "$tmp/ca.pem" ||
    die "could not fetch the platform's CA from $url/v1/ca (is Setup finished there?)"
ca=$(canonical_ca "$tmp/ca.pem" "$tmp/ca-trusted.pem") || exit 1
[ "$ca" = "$fp" ] || die "the platform's CA has fingerprint $ca, not the expected $fp"
curl -fsS --cacert "$tmp/ca-trusted.pem" --max-time 10 "$url/v1/ca" -o /dev/null ||
    die "the server at $url does not hold a certificate from that CA"

# An agent package already installed (an image, the lab's own build, a
# pinned version) is kept: apt and pacman would replace it with the
# repository's newest, which dnf install never does.
if installed openvibes-agent; then
    say "openvibes-agent is already installed; configuring it"
else
    install_package openvibes-agent
fi
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
# Threat alarms only for an agent that knows the collector: the P14 agent
# package ships its exec audit rule (in rules.d; from agent #57 on, as a
# template in /usr/share, copied to rules.d only on audit-fallback hosts);
# an older agent would refuse the name.
audit_rule=/etc/audit/rules.d/openvibes-agent.rules
alarms=''
if [ -n "$alarm_rules" ] && [ ! -f "$audit_rule" ] &&
    [ ! -f /usr/share/openvibes-agent/openvibes-agent.rules ]; then
    say "this agent has no threat alarms (needs openvibes-agent 0.2 or later); --alarm-rules ignored"
elif [ -n "$alarm_rules" ]; then
    alarms=yes
    # Ports and services for the asset view (P15) only for an agent that
    # knows the collector: its package lists the owners.conf drop-in (by
    # file list, so a nodocs install counts too). An older agent would
    # refuse the name; without this list its own default applies.
    services=''
    if package_files openvibes-agent 2>/dev/null | grep -q '/owners\.conf$'; then
        services=', "services"'
    fi
    cat >> "$tmp/agent.toml" <<EOF
# Threat alarms: the agent's eBPF watcher, or kernel audit (auditd) as the fallback.
collectors = ["processes", "packages", "ports", "process_events"$services]
EOF
fi
# Fedora's default audit rules switch syscall auditing off for every task,
# so an agent reading kernel audit (its rule in rules.d: an audit-fallback
# host) sees no program starts. Say so; never edit the host's audit rules (a
# system setting). An eBPF host's agent does not read audit.
if [ -n "$alarms" ] && [ -f "$audit_rule" ] && grep -Eq '^-a[[:space:]]+(task,never|never,task)' /etc/audit/audit.rules 2>/dev/null; then
    say "warning: threat alarms can't fire on this host: /etc/audit/audit.rules has '-a task,never'"
    say "  fix: comment it out in /etc/audit/rules.d/audit.rules and run 'augenrules --load' (new logins and restarted services are watched; a reboot covers everything)"
fi
if [ -n "$rules" ]; then
    cat >> "$tmp/agent.toml" <<EOF
distribution_url = "https://$host${dport:+:$dport}"

[[rule_sets]]
id = "$rule_set"
trusted_keys = [{ issuer_key_id = "$rule_issuer", public_key = "$rule_key" }]
EOF
fi
if [ -n "$alarms" ]; then
    cat >> "$tmp/agent.toml" <<EOF

[[rule_sets]]
id = "$alarm_set"
trusted_keys = [{ issuer_key_id = "$alarm_issuer", public_key = "$alarm_key" }]
EOF
fi
(umask 077 && printf '%s\n' "$token" > "$tmp/token")
install -m 0644 "$tmp/ca-trusted.pem" "$AGENT_DIR/platform-ca.crt"
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
