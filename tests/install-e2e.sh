#!/usr/bin/env bash
# The installer end to end, in podman containers with systemd, against a
# local repository signed with a throwaway key (releases spec §6):
#   1. platform: install.sh (no terminal: prints the next steps), setup
#      --quick with the baseline rules published, openvibes-admin agent
#      command → the one-line agent command;
#   2. agent: that command enrolls the agent (install.sh --agent) and,
#      through its --rules, the agent fetches and accepts the baseline;
#   3. refusals, each leaving no agent package behind: a wrong package-key
#      fingerprint, a wrong CA fingerprint, a server whose certificate is
#      not from the CA it serves, Fedora 43 and Debian, and an agent that
#      is already configured (its agent.toml unchanged).
# Usage: tests/install-e2e.sh RPM_DIR
#   RPM_DIR  openvibes-{ingest,distribution,vulns,admin}-*.rpm, one
#            openvibes-agent-*.rpm and openvibes-rules-baseline-*.noarch.rpm
#            (debuginfo and other files are ignored)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PODMAN=${PODMAN:-podman}
NET=ov-install-e2e
W=$ROOT/target/install-e2e
IMAGE=ov-install-e2e:44
[[ $# == 1 ]] || { echo "usage: $0 RPM_DIR" >&2; exit 2; }
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }
in_c() { "$PODMAN" exec "$1" bash -c "$2"; }
names=(repo platform agent agent2 platform2 f43 debian)
cleanup() {
    local status=$?
    if ((status != 0)); then
        for c in platform agent; do
            echo "--- $c: openvibes-ingest, openvibes-agent"
            "$PODMAN" exec "$c" journalctl -u openvibes-ingest -u openvibes-agent --no-pager -n 20 2>/dev/null || true
        done
    fi
    # KEEP=1 leaves the containers for inspection after a failure.
    if ((status != 0)) && [[ -n ${KEEP:-} ]]; then exit "$status"; fi
    "$PODMAN" rm -f "${names[@]}" >/dev/null 2>&1 || true
    "$PODMAN" network rm -f "$NET" >/dev/null 2>&1 || true
    exit "$status"
}
trap cleanup EXIT
wait_for() { # DESC SECONDS CONTAINER COMMAND
    local i
    for ((i = 0; i < $2; i++)); do
        if in_c "$3" "$4" >/dev/null 2>&1; then ok "$1"; return 0; fi
        sleep 1
    done
    fail "$1 (after $2 s)"
}

# The repository: every RPM signed with a throwaway key, indexed, the
# metadata signed; install.sh and the public key beside it.
rm -rf "$W"; mkdir -p "$W/repo/rpm/fedora/44/x86_64"
for f in "$1"/openvibes-{ingest,distribution,vulns,admin,agent}-[0-9]*.x86_64.rpm \
    "$1"/openvibes-rules-baseline-[0-9]*.noarch.rpm; do
    cp "$f" "$W/repo/rpm/fedora/44/x86_64/"
done
cp "$ROOT/install.sh" "$ROOT/scripts/sign-rpms.sh" "$W/"
# shellcheck disable=SC2016  # expands inside the container
"$PODMAN" run --rm -v "$W:/w:z" registry.fedoraproject.org/fedora:44 bash -c '
    set -e
    dnf -q -y install rpm-build rpm-sign gnupg2 createrepo_c >/dev/null 2>&1
    export GNUPGHOME=/tmp/g; mkdir -m 0700 $GNUPGHOME
    gpg --batch --pinentry-mode loopback --passphrase pw --quick-gen-key "test <t@example.invalid>" rsa2048 sign 1d 2>/dev/null
    fpr=$(gpg --with-colons --list-secret-keys | awk -F: "\$1==\"fpr\"{print \$10; exit}")
    gpg --armor --export "$fpr" > /w/repo/openvibes.gpg
    echo "$fpr" > /w/fpr
    export RPM_SIGNING_KEY=$(gpg --batch --pinentry-mode loopback --passphrase pw --armor --export-secret-keys "$fpr")
    export RPM_SIGNING_PASSPHRASE=pw
    bash /w/sign-rpms.sh /w/repo/rpm/fedora/44/x86_64 /w/repo/openvibes.gpg
    createrepo_c --quiet /w/repo/rpm/fedora/44/x86_64
    printf pw > /tmp/pass
    gpg --batch --yes --pinentry-mode loopback --passphrase-file /tmp/pass --detach-sign --armor \
        /w/repo/rpm/fedora/44/x86_64/repodata/repomd.xml
    cp /w/install.sh /w/repo/install.sh' >/dev/null || fail "sign the test repository"
FPR=$(cat "$W/fpr")
ENV="OPENVIBES_SITE=http://repo:8000 OPENVIBES_KEY_FINGERPRINT=$FPR"
ok "test repository signed ($FPR)"

# Images: systemd without gnupg2 (the installer adds it), a web server.
# udev's default MAC policy would give eth0 a new address when systemd
# boots in the container, so replies to podman's address never arrive and
# the other containers cannot reach it: keep podman's MAC.
printf 'FROM registry.fedoraproject.org/fedora:44
RUN dnf -q -y install systemd postgresql-server procps-ng util-linux curl polkit sudo && dnf -q -y remove gnupg2 || true; dnf clean all
RUN mkdir -p /etc/systemd/network && printf "[Match]\\nOriginalName=*\\n[Link]\\nMACAddressPolicy=none\\n" > /etc/systemd/network/99-default.link
' | "$PODMAN" build -q -t "$IMAGE" -f - "$W" >/dev/null
"$PODMAN" network create "$NET" >/dev/null
# Names go into each container's /etc/hosts: container DNS on a user
# network is missing on some hosts (the GitHub runner's podman).
HOSTS=()
known() { # NAME: later containers can reach it by name
    HOSTS+=(--add-host "$1:$("$PODMAN" inspect "$1" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')")
}
"$PODMAN" run -d --name repo --network "$NET" -v "$W/repo:/srv:z" -w /srv \
    registry.fedoraproject.org/fedora:44 bash -c 'dnf -q -y install python3 >/dev/null 2>&1; exec python3 -m http.server 8000' >/dev/null
known repo
systemd_container() { # NAME
    "$PODMAN" run -d --name "$1" --hostname "$1" --network "$NET" "${HOSTS[@]}" --systemd=always --privileged \
        -v "$W:/test:z" "$IMAGE" /sbin/init >/dev/null
    wait_for "$1 is up" 60 "$1" 'systemctl is-system-running | grep -qE "running|degraded"'
}
systemd_container platform
known platform
wait_for "the repository answers" 60 platform 'curl -fsS http://repo:8000/openvibes.gpg -o /dev/null'

# 1. The platform through the installer and Setup.
out=$(in_c platform "$ENV sh /test/install.sh" 2>&1) || { echo "$out"; fail "install.sh (platform)"; }
grep -q "setup --quick" <<<"$out" || { echo "$out"; fail "no next steps without a terminal"; }
in_c platform 'command -v gpg >/dev/null' || fail "gnupg2 was not installed"
in_c platform 'rpm -q --quiet openvibes-admin' || fail "openvibes-admin not installed"
in_c platform 'openvibes-admin setup --quick --components ingest,distribution,vulns,rules --hostname platform --san 127.0.0.1' \
    > "$W/setup.out" 2>&1 || { cat "$W/setup.out"; fail "setup --quick"; }
LINE=$(in_c platform 'runuser -u openvibes-admin -- openvibes-admin agent command --platform platform' | head -1)
[[ $LINE == "curl -fsSL https://openvibes-project.github.io/install.sh | sudo sh -s -- --agent "* ]] || fail "agent command: $LINE"
ARGS=${LINE#*sh -s -- }
in_c platform 'runuser -u openvibes-admin -- openvibes-admin rules list' | grep -q '^baseline v[0-9]' ||
    { cat "$W/setup.out"; fail "baseline rules not published by Setup"; }
ok "platform installed through install.sh and Setup; baseline rules published; agent command printed"

# 2. An agent through the printed command.
systemd_container agent
out=$(in_c agent "$ENV sh /test/install.sh $ARGS" 2>&1) || { echo "$out"; fail "install.sh --agent"; }
grep -q "enrolled as agent\." <<<"$out" || { echo "$out"; fail "no 'enrolled as'"; }
wait_for "the platform lists the agent as active" 30 platform \
    'runuser -u openvibes-admin -- openvibes-admin agent list | grep -q "  active  "'
ok "agent enrolled through the one-line command"
grep -q -- " --rules baseline," <<<"$LINE" || fail "agent command has no --rules: $LINE"
AGENT_ID=$(in_c platform 'runuser -u openvibes-admin -- openvibes-admin agent list' | awk 'NR == 1 {print $1}')
wait_for "the agent accepted the baseline rule set" 180 platform \
    "runuser -u openvibes-admin -- openvibes-admin agent show $AGENT_ID | grep -q '^rule set baseline version [0-9]'"
ok "the enrolled agent fetched and accepted the baseline rule set"

# 3. Refusals: each exits non-zero and installs no agent.
refused() { # DESC CONTAINER ARGS…
    local desc=$1 c=$2; shift 2
    if in_c "$c" "$*" >/dev/null 2>&1; then fail "$desc: accepted"; fi
    if in_c "$c" 'rpm -q --quiet openvibes-agent' 2>/dev/null; then fail "$desc: agent installed"; fi
    ok "$desc: refused"
}
# A server that serves the platform's real root but holds a certificate
# from another CA: the fingerprint matches, the server check must not.
in_c platform 'cat /etc/openvibes/pki/root.crt' > "$W/root1.pem"
"$PODMAN" run -d --name platform2 --hostname platform2 --network "$NET" "${HOSTS[@]}" -v "$W:/test:z" \
    registry.fedoraproject.org/fedora:44 bash -c '
        dnf -q -y install openssl >/dev/null 2>&1
        mkdir -p /srv/v1 && cp /test/root1.pem /srv/v1/ca && cd /srv
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
            -subj /CN=platform2 -addext subjectAltName=DNS:platform2 -keyout /k.pem -out /c.pem 2>/dev/null
        exec openssl s_server -quiet -accept 18423 -cert /c.pem -key /k.pem -WWW' >/dev/null
known platform2
systemd_container agent2
TOKEN=$(sed -n 's/.*--token \([^ ]*\).*/\1/p' <<<"$ARGS")
FP=$(sed -n 's/.*--ca-sha256 \([^ ]*\).*/\1/p' <<<"$ARGS")
refused "a wrong package key" agent2 \
    "OPENVIBES_SITE=http://repo:8000 OPENVIBES_KEY_FINGERPRINT=$(printf '0%.0s' {1..40}) sh /test/install.sh $ARGS"
refused "a malformed --rules" agent2 \
    "$ENV sh /test/install.sh --agent --platform platform --token $TOKEN --ca-sha256 $FP --rules 'baseline,x;y,z'"
refused "a wrong CA fingerprint" agent2 \
    "$ENV sh /test/install.sh --agent --platform platform --token $TOKEN --ca-sha256 $(printf '0%.0s' {1..64})"
wait_for "the foreign server answers" 60 agent2 'curl -ksf https://platform2:18423/v1/ca -o /dev/null'
refused "a server whose certificate is not from that CA" agent2 \
    "$ENV sh /test/install.sh --agent --platform platform2 --token $TOKEN --ca-sha256 $FP"
for image in registry.fedoraproject.org/fedora:43 docker.io/library/debian:stable; do
    name=$([[ $image == *fedora* ]] && echo f43 || echo debian)
    "$PODMAN" run -d --name "$name" --network "$NET" -v "$W:/test:z" "$image" sleep infinity >/dev/null
    if in_c "$name" "$ENV sh /test/install.sh $ARGS" >"$W/$name.out" 2>&1; then fail "$image: accepted"; fi
    grep -q "Fedora 44 on x86_64" "$W/$name.out" || { cat "$W/$name.out"; fail "$image: wrong refusal"; }
    ok "$image: refused"
done
before=$(in_c agent 'sha256sum /etc/openvibes-agent/agent.toml')
if in_c agent "$ENV sh /test/install.sh $ARGS" >/dev/null 2>&1; then fail "a configured agent was overwritten"; fi
[[ "$(in_c agent 'sha256sum /etc/openvibes-agent/agent.toml')" == "$before" ]] || fail "agent.toml changed"
ok "an already configured agent: refused, agent.toml unchanged"
echo "install-e2e: all checks passed"
