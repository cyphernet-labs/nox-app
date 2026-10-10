#!/usr/bin/env bash
#
# Installs the NOX server on Linux, and the NOX onion service in the system's
# tor - a service of its own.
#
#   sudo deploy/install-linux.sh [--port 8443] [--public-addr host:port] [--no-tor]
#
# One run does everything: the server's account and folders, the server
# (built from this repository, or --binary), tor 0.4.9 or newer - the
# distribution's package when it is new enough, otherwise the Tor Project's
# repository, whose packages are signed - the NOX onion service added to tor
# without touching its other settings, the server as a systemd service that
# starts with the machine, the server's password, and at the end the link and
# QR code for the first device. A run on a machine that already has a server
# updates it: the database, the password and the onion address's key are left
# alone.
#
# Checking the script without changing the system:
#
#   deploy/install-linux.sh --prefix DIR --no-service --tor-bin PATH [--port P --status-port S]
#
# puts every file under DIR, creates no accounts, installs no packages and
# registers nothing with systemd: the server, and a tor of its own when one is
# given, run as background processes of whoever ran it.

set -euo pipefail
# Never traced: a trace prints every expanded word, the password among them.
set +x
umask 022

DEPLOY_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_DIR=$(dirname "$DEPLOY_DIR")
# shellcheck source=install-common.sh
. "$DEPLOY_DIR/install-common.sh"

SERVER_ACCOUNT=nox
SERVICE=noxd

# The Tor Project's package repositories and the keys they are signed with,
# by fingerprint (support.torproject.org: apt and rpm). A downloaded key file
# is used only when every key in it is this one, and what is installed is
# that key alone, as gpg reads it.
TOR_APT_KEY=A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89
TOR_APT_KEY_URL=https://deb.torproject.org/torproject.org/$TOR_APT_KEY.asc
TOR_APT_REPO=https://deb.torproject.org/torproject.org
TOR_APT_KEYRING=/usr/share/keyrings/deb.torproject.org-keyring.gpg
TOR_APT_LIST=/etc/apt/sources.list.d/tor.list
TOR_RPM_KEY=999EC8E314BC8D46022D6C7DE217C30C3621CD35
TOR_RPM_KEY_FILE=/etc/pki/rpm-gpg/RPM-GPG-KEY-torproject
TOR_RPM_REPO_FILE=/etc/yum.repos.d/tor.repo

usage() {
	cat <<EOF
Installs the NOX server on this machine, and the NOX onion service in tor.

  sudo $0 [options]

Options:
  --port N            the server's port (default $NOX_DEFAULT_PORT; on an update, the one in use)
  --status-port N     the service page's port, on this machine only (default $NOX_DEFAULT_STATUS_PORT)
  --public-addr H:P   the address devices reach this machine at from the internet, if any
  --binary PATH       install this noxd instead of building one (needs no Go)
  --no-tor            no tor: devices connect directly only
  --prefix DIR        check the script without changing the system: every file under DIR,
  --no-service          no accounts, no packages, no systemd - give both
  --tor-bin PATH      with --prefix: the tor to run for the check (default: tor on the PATH)
  -h, --help          this text

Run again to update: the database, the password and the onion address stay.
EOF
}

# set_paths lays the installation out - under the prefix when checking. The
# system's tor keeps its own files; a check runs a tor of its own.
set_paths() {
	ROOT=$OPT_PREFIX
	NOXD="$ROOT/usr/local/bin/noxd"
	DATA_DIR="$ROOT/var/lib/nox"
	DB="$DATA_DIR/nox.db"
	UNIT="$ROOT/etc/systemd/system/$SERVICE.service"
	if [ -n "$OPT_PREFIX" ]; then
		LOG_DIR="$ROOT/var/log/nox"
		SERVER_LOG="$LOG_DIR/noxd.log"
		TOR_LOG="$LOG_DIR/tor.log"
		TOR_ETC="$ROOT/etc/nox-tor"
		TORRC="$TOR_ETC/torrc"
		TOR_DEFAULTS="$TOR_ETC/torrc-defaults"
		NOX_TOR_CONF="$TOR_ETC/nox-tor.conf"
		TOR_DATA="$ROOT/var/lib/nox-tor"
		HS_DIR="$TOR_DATA/nox"
		RUN_DIR="$ROOT/run/nox"
		SERVER_USER=$(id -un)
		SERVER_GROUP=$(id -gn)
		NOXD_CMD=$NOXD
	else
		SERVER_LOG="journalctl -u $SERVICE"
		TORRC=/etc/tor/torrc
		NOX_TOR_CONF=/etc/tor/nox-tor.conf
		HS_DIR=/var/lib/tor/nox
		TOR_LOG="journalctl -u tor@default -u tor"
		RUN_DIR=""
		SERVER_USER=$SERVER_ACCOUNT
		SERVER_GROUP=$SERVER_ACCOUNT
		NOXD_CMD=noxd
	fi
}

# previous_arg FLAG prints the value that follows FLAG in the installed unit's
# command line, or nothing.
previous_arg() {
	[ -f "$UNIT" ] || return 0
	awk -v flag="$1" '
		/^ExecStart=/ {
			sub(/^ExecStart=/, "")
			n = split($0, w, /[ \t]+/)
			for (i = 1; i < n; i++) if (w[i] == flag) { v = w[i + 1]; gsub(/"/, "", v); print v; exit }
		}' "$UNIT" || true
}

detect_install() {
	local prev
	UPDATE=0
	FRESH_DATA=1
	if [ -e "$DB" ] || [ -e "$DB.key" ]; then
		FRESH_DATA=0
		UPDATE=1
	fi
	if [ -f "$UNIT" ]; then
		UPDATE=1
	fi
	PORT=$OPT_PORT
	if [ -z "$PORT" ]; then
		prev=$(previous_arg -addr)
		PORT=${prev##*:}
		valid_port "$PORT" || PORT=$NOX_DEFAULT_PORT
	fi
	STATUS_PORT=$OPT_STATUS_PORT
	if [ -z "$STATUS_PORT" ]; then
		prev=$(previous_arg -status-addr)
		STATUS_PORT=${prev##*:}
		valid_port "$STATUS_PORT" || STATUS_PORT=$NOX_DEFAULT_STATUS_PORT
	fi
	PUBLIC_ADDR=$OPT_PUBLIC_ADDR
	if [ -z "$PUBLIC_ADDR" ]; then
		PUBLIC_ADDR=$(previous_arg -public-addr)
	fi
}

# port_holder names the program listening on TCP port $1, or prints nothing.
port_holder() {
	local out name=""
	if command -v ss >/dev/null 2>&1; then
		out=$(ss -ltnp "sport = :$1" 2>/dev/null | tail -n +2) || true
		if [ -n "$out" ]; then
			name=$(printf '%s\n' "$out" | sed -n 's/.*users:(("\([^"]*\)".*/\1/p' | head -n 1) || true
			[ -n "$name" ] || name="another program"
		fi
	fi
	if [ -z "$name" ] && listening_here "$1"; then
		name="another program"
	fi
	printf '%s' "$name"
}

own_server_running() {
	if [ -n "$OPT_PREFIX" ]; then
		bg_running noxd "$RUN_DIR/noxd.pid"
	else
		systemctl is-active --quiet "$SERVICE" 2>/dev/null
	fi
}

# unprivileged_port_start prints the lowest port an account other than root
# may listen on - 1024 unless the system says otherwise. The service is not
# given CAP_NET_BIND_SERVICE: a port below it is refused before anything
# changes, and the server keeps no right it does not need - a router forwards
# 443 to 8443 just as well.
unprivileged_port_start() {
	local start
	start=$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null) || true
	case $start in
	'' | *[!0-9]*) start=1024 ;;
	esac
	printf '%s' "$start"
}

# --- account and folders -----------------------------------------------------

ensure_account() {
	local uid shell
	if id -u "$SERVER_ACCOUNT" >/dev/null 2>&1; then
		uid=$(id -u "$SERVER_ACCOUNT")
		[ "$uid" -lt 1000 ] || die "there is an account named $SERVER_ACCOUNT that is not a system account (uid $uid); the server will not run as somebody's own account"
		return 0
	fi
	shell=$(command -v nologin 2>/dev/null || true)
	[ -n "$shell" ] || shell=/usr/sbin/nologin
	useradd --system --user-group --home-dir "$DATA_DIR" --no-create-home --shell "$shell" \
		--comment "NOX server" "$SERVER_ACCOUNT" || die "cannot create the account $SERVER_ACCOUNT"
	undo_push "userdel $SERVER_ACCOUNT 2>/dev/null; groupdel $SERVER_ACCOUNT 2>/dev/null || true"
	note "account $SERVER_ACCOUNT created"
}

install_layout() {
	if [ -n "$OPT_PREFIX" ]; then
		make_dir "$(dirname "$NOXD")" "" "" 755
		make_dir "$(dirname "$UNIT")" "" "" 755
		make_dir "$LOG_DIR" "" "" 755
		make_dir "$RUN_DIR" "" "" 755
		make_own_dir "$DATA_DIR" "" "" 700
		if [ ! -e "$SERVER_LOG" ]; then
			: >"$SERVER_LOG"
			undo_push "rm -f $(q "$SERVER_LOG")"
		fi
	else
		step "Account and folders"
		ensure_account
		make_dir "$(dirname "$NOXD")" root root 755
		make_own_dir "$DATA_DIR" "$SERVER_ACCOUNT" "$SERVER_ACCOUNT" 700
	fi
}

install_binary() {
	step "Installing the server at $NOXD"
	if [ -n "$OPT_PREFIX" ]; then
		put_file "$NEW_BINARY" "$NOXD" 755
	else
		put_file "$NEW_BINARY" "$NOXD" 755 root root
		if command -v restorecon >/dev/null 2>&1; then
			restorecon "$NOXD" 2>/dev/null || true
		fi
	fi
}

# --- tor ---------------------------------------------------------------------

TOR_PROBLEM=""
ONION=""

tor_fail() {
	TOR_PROBLEM=$1
	return 1
}

fetch() {
	curl -fsSL --proto '=https' --retry 2 --connect-timeout 30 --max-time 300 -o "$2" "$1"
}

# key_file_is FILE FPR succeeds when every key in FILE is the one whose
# primary fingerprint is FPR: at least one, and no other beside it. apt trusts
# every key in a signed-by keyring and rpm imports every key in a file, so a
# key put after the genuine one would be trusted as much as the genuine one.
key_file_is() {
	local home listing
	home=$(mktemp -d "$WORK/gnupg.XXXXXX")
	chmod 700 "$home"
	listing=$(gpg --homedir "$home" --batch --no-autostart --with-colons --import-options show-only --import "$1" 2>/dev/null) || true
	printf '%s\n' "$listing" | awk -F: -v fpr="$2" '
		$1 == "pub" { keys++; primary = 1; next }
		$1 == "fpr" && primary { if ($10 == fpr) pinned++; primary = 0; next }
		{ primary = 0 }
		END { exit !(keys > 0 && pinned == keys) }'
}

# pinned_key FILE FPR OUT [--armor] writes to OUT the key FPR from FILE, and
# nothing else: FILE must hold that key alone, and OUT is gpg's own reading of
# it, without what gpg finds invalid - a subkey with no valid binding to the
# key, for one - checked again. No keyring is written: gpg imports into its
# output.
pinned_key() {
	local file=$1 fpr=$2 out=$3 home
	shift 3
	key_file_is "$file" "$fpr" || return 1
	home=$(mktemp -d "$WORK/gnupg.XXXXXX")
	chmod 700 "$home"
	gpg --homedir "$home" --batch --no-autostart "$@" --import-options import-export --import "$file" >"$out" 2>/dev/null ||
		return 1
	key_file_is "$out" "$fpr"
}

os_release() {
	# shellcheck disable=SC1091
	(. /etc/os-release 2>/dev/null && eval "printf '%s' \"\${$1:-}\"") || true
}

# upstream_version turns a package version (1:0.4.9.3-1~bookworm+1) into the
# tor version it carries (0.4.9.3).
upstream_version() {
	local v=${1#*:}
	printf '%s' "${v%%[-~+]*}"
}

# rpm_keys lists the keys rpm holds, one package name per line.
rpm_keys() {
	rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}\n' 'gpg-pubkey*' 2>/dev/null || true
}

# rpm_import_key FILE gives rpm the key in FILE and records how to take it out
# again - unless rpm had it already.
rpm_import_key() {
	local before k
	before=$(rpm_keys)
	rpm --import "$1" || return 1
	for k in $(rpm_keys); do
		case "
$before
" in
		*"
$k
"*) ;;
		*) undo_push "rpm -e $(q "$k") >/dev/null 2>&1 || true" ;;
		esac
	done
}

# The record keeps what this run installed: a package that was not here is
# removed again if tor cannot be set up.
apt_install() {
	local pkg had=()
	for pkg in "$@"; do
		if dpkg -s "$pkg" >/dev/null 2>&1; then had[${#had[@]}]=$pkg; fi
	done
	DEBIAN_FRONTEND=noninteractive apt-get install -y -q -o Dpkg::Options::=--force-confold "$@" ||
		tor_fail "apt-get could not install $*" || return 1
	for pkg in "$@"; do
		case " ${had[*]+${had[*]}} " in
		*" $pkg "*) ;;
		*) undo_push "DEBIAN_FRONTEND=noninteractive apt-get remove -y -q $pkg >/dev/null 2>&1 || true" ;;
		esac
	done
}

# apt_tor_project adds the Tor Project's repository: its key, by fingerprint,
# and the source list signed by it. apt then refuses any package of it that
# the key did not sign.
apt_tor_project() {
	local codename
	codename=$(os_release UBUNTU_CODENAME)
	[ -n "$codename" ] || codename=$(os_release VERSION_CODENAME)
	[ -n "$codename" ] || tor_fail "cannot tell this distribution's release name for the Tor Project's repository" || return 1
	if ! command -v gpg >/dev/null 2>&1; then
		apt_install gnupg || return 1
	fi
	note "adding the Tor Project's repository ($codename)"
	fetch "$TOR_APT_KEY_URL" "$WORK/tor-apt.asc" || tor_fail "could not download the Tor Project's repository key (no network?)" || return 1
	pinned_key "$WORK/tor-apt.asc" "$TOR_APT_KEY" "$WORK/tor-apt.gpg" ||
		tor_fail "the downloaded repository key file is not the Tor Project's key ($TOR_APT_KEY) and nothing else; tor was not installed" || return 1
	make_dir "$(dirname "$TOR_APT_KEYRING")" root root 755
	put_file "$WORK/tor-apt.gpg" "$TOR_APT_KEYRING" 644 root root
	printf 'deb [signed-by=%s] %s %s main\n' "$TOR_APT_KEYRING" "$TOR_APT_REPO" "$codename" >"$WORK/tor.list"
	put_file "$WORK/tor.list" "$TOR_APT_LIST" 644 root root
	apt-get update -q >/dev/null 2>&1 ||
		tor_fail "apt-get update failed with the Tor Project's repository - is $codename one it serves?" || return 1
}

apt_tor() {
	local candidate
	note "looking for tor in the package lists"
	apt-get update -q >/dev/null 2>&1 || tor_fail "apt-get update failed (no network?)" || return 1
	candidate=$(apt-cache policy tor 2>/dev/null | awk '/Candidate:/ { print $2; exit }') || true
	if [ -n "$candidate" ] && [ "$candidate" != "(none)" ] &&
		version_at_least "$(upstream_version "$candidate")" "$NOX_TOR_MIN_VERSION"; then
		apt_install tor || return 1
		[ -z "$(tor_unsuitable "$(command -v tor)")" ] && return 0
		note "the distribution's tor has no proof-of-work support"
	fi
	apt_tor_project || return 1
	apt_install tor deb.torproject.org-keyring || return 1
}

dnf_tor() {
	local candidate base key
	note "looking for tor in the package lists"
	candidate=$(dnf -q info tor 2>/dev/null | awk -F: '/^Version/ { gsub(/[ \t]/, "", $2); print $2 }' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -n 1) || true
	if [ -n "$candidate" ] && version_at_least "$candidate" "$NOX_TOR_MIN_VERSION"; then
		if ! rpm -q tor >/dev/null 2>&1; then
			dnf install -y -q tor || tor_fail "dnf could not install tor" || return 1
			undo_push "dnf remove -y -q tor >/dev/null 2>&1 || true"
		else
			dnf upgrade -y -q tor || tor_fail "dnf could not upgrade tor" || return 1
		fi
		[ -z "$(tor_unsuitable "$(command -v tor)")" ] && return 0
		note "the distribution's tor has no proof-of-work support"
	fi
	base=centos
	if [ "$(os_release ID)" = fedora ]; then base=fedora; fi
	if [ "$base" = centos ] && ! rpm -q epel-release >/dev/null 2>&1; then
		dnf install -y -q epel-release || note "could not add EPEL; the Tor Project's packages may need it"
	fi
	key=https://rpm.torproject.org/$base/public_gpg.key
	note "adding the Tor Project's repository ($base)"
	fetch "$key" "$WORK/tor-rpm.key" || tor_fail "could not download the Tor Project's repository key (no network?)" || return 1
	command -v gpg >/dev/null 2>&1 || tor_fail "there is no gpg to check the repository key with" || return 1
	pinned_key "$WORK/tor-rpm.key" "$TOR_RPM_KEY" "$WORK/tor-rpm.asc" --armor ||
		tor_fail "the downloaded repository key file is not the Tor Project's key ($TOR_RPM_KEY) and nothing else; tor was not installed" || return 1
	# dnf gets this checked copy and never the address: told to fetch a key
	# itself, dnf -y imports whatever key the address serves, unchecked.
	make_dir "$(dirname "$TOR_RPM_KEY_FILE")" root root 755
	put_file "$WORK/tor-rpm.asc" "$TOR_RPM_KEY_FILE" 644 root root
	if command -v restorecon >/dev/null 2>&1; then
		restorecon "$TOR_RPM_KEY_FILE" 2>/dev/null || true
	fi
	rpm_import_key "$TOR_RPM_KEY_FILE" || tor_fail "rpm did not take the repository key" || return 1
	cat >"$WORK/tor.repo" <<EOF
[tor]
name=Tor Project packages
baseurl=https://rpm.torproject.org/$base/\$releasever/\$basearch
enabled=1
gpgcheck=1
gpgkey=file://$TOR_RPM_KEY_FILE
cost=100
EOF
	put_file "$WORK/tor.repo" "$TOR_RPM_REPO_FILE" 644 root root
	if rpm -q tor >/dev/null 2>&1; then
		dnf upgrade -y -q tor || tor_fail "dnf could not upgrade tor from the Tor Project's repository" || return 1
	else
		dnf install -y -q tor || tor_fail "dnf could not install tor from the Tor Project's repository" || return 1
		undo_push "dnf remove -y -q tor >/dev/null 2>&1 || true"
	fi
}

pacman_tor() {
	local candidate
	candidate=$(pacman -Si tor 2>/dev/null | awk -F: '/^Version/ { gsub(/[ \t]/, "", $2); print $2; exit }') || true
	[ -n "$candidate" ] && version_at_least "$(upstream_version "$candidate")" "$NOX_TOR_MIN_VERSION" ||
		tor_fail "the distribution's tor is older than $NOX_TOR_MIN_VERSION; install a newer one yourself and run the script again" || return 1
	if ! pacman -Q tor >/dev/null 2>&1; then
		pacman -S --needed --noconfirm tor || tor_fail "pacman could not install tor" || return 1
		undo_push "pacman -R --noconfirm tor >/dev/null 2>&1 || true"
	fi
}

# system_tor sets TOR_EXE to the system's tor, installing or upgrading the
# package when the one here is missing, too old, or without proof of work.
system_tor() {
	local bin why
	bin=$(command -v tor 2>/dev/null || true)
	if [ -n "$bin" ]; then
		why=$(tor_unsuitable "$bin")
		if [ -z "$why" ]; then
			TOR_EXE=$bin
			note "using the system's tor ($(tor_version "$bin"))"
			return 0
		fi
		note "the tor here cannot carry the onion service: $why"
	fi
	if command -v apt-get >/dev/null 2>&1; then
		apt_tor || return 1
	elif command -v dnf >/dev/null 2>&1; then
		dnf_tor || return 1
	elif command -v pacman >/dev/null 2>&1; then
		pacman_tor || return 1
	else
		tor_fail "no package manager this script knows (apt, dnf, pacman); install tor $NOX_TOR_MIN_VERSION or newer yourself and run the script again" || return 1
	fi
	bin=$(command -v tor 2>/dev/null || true)
	[ -n "$bin" ] || tor_fail "tor was installed, but there is no tor on the PATH" || return 1
	why=$(tor_unsuitable "$bin")
	[ -z "$why" ] || tor_fail "the installed tor cannot carry the onion service: $why" || return 1
	TOR_EXE=$bin
	note "tor $(tor_version "$bin") installed"
}

TOR_INCLUDE_BEGIN="# BEGIN NOX - written by the NOX install script"
TOR_INCLUDE_END="# END NOX"

# include_nox_conf adds the NOX onion service to the system's torrc - one
# %include of the NOX file, between markers - and changes nothing else in it.
include_nox_conf() {
	if [ -f "$TORRC" ] && grep -qxF "$TOR_INCLUDE_BEGIN" "$TORRC"; then
		return 0
	fi
	if [ -f "$TORRC" ]; then
		cp -p "$TORRC" "$WORK/torrc.edit"
	else
		: >"$WORK/torrc.edit"
	fi
	printf '\n%s\n%%include %s\n%s\n' "$TOR_INCLUDE_BEGIN" "$NOX_TOR_CONF" "$TOR_INCLUDE_END" >>"$WORK/torrc.edit"
	put_file "$WORK/torrc.edit" "$TORRC" 644 root root
}

# tor_defaults is the defaults file the distribution's service starts tor
# with, so the check below sees what the service will.
tor_defaults() {
	local f
	for f in /usr/share/tor/tor-service-defaults-torrc /usr/share/tor/defaults-torrc; do
		if [ -f "$f" ]; then
			printf '%s' "$f"
			return 0
		fi
	done
}

# tor_unit is the unit that runs the system's tor: tor@default on Debian and
# Ubuntu, where tor.service only groups the instances; tor elsewhere.
tor_unit() {
	local units
	units=$(systemctl list-unit-files 'tor@.service' 2>/dev/null) || true
	case $units in
	*tor@.service*) printf 'tor@default' ;;
	*) printf 'tor' ;;
	esac
}

setup_tor_system() {
	local defaults out unit
	step "tor"
	system_tor || return 1
	# Last when undoing: tor runs again on its own settings, restored by then.
	undo_push "systemctl restart tor >/dev/null 2>&1 || true"
	render "$DEPLOY_DIR/nox-tor.conf.tmpl" "$WORK/nox-tor.conf" HS_DIR="$(torq "$HS_DIR")" PORT="$PORT"
	put_file "$WORK/nox-tor.conf" "$NOX_TOR_CONF" 644 root root
	include_nox_conf
	if command -v restorecon >/dev/null 2>&1; then
		restorecon "$NOX_TOR_CONF" "$TORRC" 2>/dev/null || true
	fi
	defaults=$(tor_defaults)
	if [ -n "$defaults" ]; then
		if ! out=$("$TOR_EXE" --defaults-torrc "$defaults" -f "$TORRC" --verify-config 2>&1); then
			out=$(printf '%s\n' "$out" | grep -E '\[(warn|err)\]' | tail -n 2 | sed 's/^.*\] //' | tr '\n' ' ') || true
			tor_fail "tor does not accept the settings with the NOX onion service: $out" || return 1
		fi
	fi
	# tor writes the address from the key on every start; without the old
	# file, the wait below proves this start. The key itself stays.
	rm -f "$HS_DIR/hostname"
	systemctl enable tor >/dev/null 2>&1 || true
	systemctl restart tor || tor_fail "systemctl could not restart tor" || return 1
	if ! ONION=$(wait_onion "$HS_DIR"); then
		unit=$(tor_unit)
		say "The end of tor's log:" >&2
		journalctl -u "$unit" -n 8 --no-pager >&2 2>/dev/null || true
		tor_fail "tor did not write its onion address within $NOX_ONION_WAIT seconds" || return 1
	fi
	note "the onion service is ready"
}

# setup_tor_check runs a tor of its own for a check under the prefix: the one
# given with --tor-bin, or the one on the PATH. Nothing is installed.
setup_tor_check() {
	local why
	step "tor"
	TOR_EXE=$OPT_TOR_BIN
	[ -n "$TOR_EXE" ] || TOR_EXE=$(command -v tor 2>/dev/null || true)
	[ -n "$TOR_EXE" ] || tor_fail "no tor for the check: pass --tor-bin, or --no-tor" || return 1
	why=$(tor_unsuitable "$TOR_EXE")
	[ -z "$why" ] || tor_fail "the tor at $TOR_EXE cannot be used: $why" || return 1
	note "using the tor at $TOR_EXE ($(tor_version "$TOR_EXE"))"
	make_dir "$TOR_ETC" "" "" 755
	make_own_dir "$TOR_DATA" "" "" 700
	if [ ! -e "$TOR_LOG" ]; then
		: >"$TOR_LOG"
		undo_push "rm -f $(q "$TOR_LOG")"
	fi
	if [ ! -e "$TORRC" ]; then
		render "$DEPLOY_DIR/torrc.tmpl" "$WORK/torrc" DATA_DIR="$(torq "$TOR_DATA")" LOG_TARGET=stdout NOX_CONF="$(torq "$NOX_TOR_CONF")"
		put_file "$WORK/torrc" "$TORRC" 644
	fi
	if [ ! -e "$TOR_DEFAULTS" ]; then
		: >"$WORK/torrc-defaults"
		put_file "$WORK/torrc-defaults" "$TOR_DEFAULTS" 644
	fi
	render "$DEPLOY_DIR/nox-tor.conf.tmpl" "$WORK/nox-tor.conf" HS_DIR="$(torq "$HS_DIR")" PORT="$PORT"
	put_file "$WORK/nox-tor.conf" "$NOX_TOR_CONF" 644
	rm -f "$HS_DIR/hostname"
	bg_stop tor "$RUN_DIR/nox-tor.pid"
	bg_start tor "$RUN_DIR/nox-tor.pid" "$TOR_LOG" "$TOR_EXE" --defaults-torrc "$TOR_DEFAULTS" -f "$TORRC"
	if ! ONION=$(wait_onion "$HS_DIR"); then
		say "The end of tor's log:" >&2
		tail -n 8 "$TOR_LOG" >&2 2>/dev/null || true
		tor_fail "tor did not write its onion address within $NOX_ONION_WAIT seconds" || return 1
	fi
	note "the onion service is ready"
}

setup_tor() {
	if [ -n "$OPT_PREFIX" ]; then
		setup_tor_check
	else
		setup_tor_system
	fi
}

# --- the server --------------------------------------------------------------

# unit_value escapes a value for a systemd command line: % starts a specifier
# there, and the value sits inside double quotes.
unit_value() {
	local v=$1
	v=${v//\%/%%}
	v=${v//\\/\\\\}
	v=${v//\"/\\\"}
	printf '%s' "$v"
}

start_server() {
	local address_args="" was_active=0
	step "Starting the server"
	if [ -n "$ONION" ]; then address_args="$address_args -onion-addr $ONION"; fi
	if [ -n "$PUBLIC_ADDR" ]; then address_args="$address_args -public-addr $PUBLIC_ADDR"; fi
	render "$DEPLOY_DIR/noxd.service.tmpl" "$WORK/noxd.service" \
		NOXD="$(unit_value "$NOXD")" PORT="$PORT" DB="$(unit_value "$DB")" STATUS_PORT="$STATUS_PORT" \
		ADDRESS_ARGS="$address_args" USER="$SERVER_USER" GROUP="$SERVER_GROUP"
	if [ -n "$OPT_PREFIX" ]; then
		bg_stop noxd "$RUN_DIR/noxd.pid"
		put_file "$WORK/noxd.service" "$UNIT" 644
		set -- -addr "0.0.0.0:$PORT" -db "$DB" -status-addr "127.0.0.1:$STATUS_PORT"
		if [ -n "$ONION" ]; then set -- "$@" -onion-addr "$ONION"; fi
		if [ -n "$PUBLIC_ADDR" ]; then set -- "$@" -public-addr "$PUBLIC_ADDR"; fi
		bg_start noxd "$RUN_DIR/noxd.pid" "$SERVER_LOG" "$NOXD" "$@"
		return 0
	fi
	if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then was_active=1; fi
	# Undone in reverse: stop the new server, put the old unit back, reload,
	# and start the old server again if it was running.
	if [ "$was_active" = 1 ]; then
		undo_push "systemctl daemon-reload; systemctl restart $SERVICE >/dev/null 2>&1 || true"
	else
		undo_push "systemctl daemon-reload"
	fi
	put_file "$WORK/noxd.service" "$UNIT" 644 root root
	systemctl daemon-reload || die "systemctl daemon-reload failed"
	if ! systemctl is-enabled --quiet "$SERVICE" 2>/dev/null; then
		systemctl enable "$SERVICE" >/dev/null 2>&1 || die "systemctl could not enable $SERVICE"
		undo_push "systemctl disable $SERVICE >/dev/null 2>&1 || true"
	fi
	systemctl restart "$SERVICE" || die "systemctl could not start $SERVICE"
	undo_push "systemctl stop $SERVICE >/dev/null 2>&1 || true"
}

server_log_tail() {
	if [ -n "$OPT_PREFIX" ]; then
		tail -n 12 "$SERVER_LOG" 2>/dev/null || true
	else
		journalctl -u "$SERVICE" -n 12 --no-pager 2>/dev/null || true
	fi
}

firewall_hint() {
	local ufw_state=""
	[ -z "$OPT_PREFIX" ] || return 0
	if command -v ufw >/dev/null 2>&1; then
		ufw_state=$(ufw status 2>/dev/null) || true
	fi
	if [ "${ufw_state#Status: active}" != "$ufw_state" ]; then
		say ""
		say "ufw is active. If phones on your network cannot connect, open the server's port:"
		say "    sudo ufw allow $PORT/tcp"
	elif command -v firewall-cmd >/dev/null 2>&1 && [ "$(firewall-cmd --state 2>/dev/null || true)" = running ]; then
		say ""
		say "firewalld is running. If phones on your network cannot connect, open the server's port:"
		say "    sudo firewall-cmd --permanent --add-port=$PORT/tcp && sudo firewall-cmd --reload"
	fi
}

summary() {
	step "Done"
	if [ -n "$OPT_PREFIX" ]; then
		say "A check under $OPT_PREFIX: nothing outside it was changed, and nothing starts with the machine."
		if [ -f "$RUN_DIR/nox-tor.pid" ]; then
			say "The server and tor run as background processes; stop them with"
			say "    kill \$(cat '$RUN_DIR/noxd.pid') \$(cat '$RUN_DIR/nox-tor.pid')"
		else
			say "The server runs as a background process; stop it with"
			say "    kill \$(cat '$RUN_DIR/noxd.pid')"
		fi
	else
		say "The NOX server is installed and starts with this machine (systemd: $SERVICE)."
	fi
	note "service page:  http://127.0.0.1:$STATUS_PORT (on this machine only)"
	note "server port:   $PORT - devices connect here directly"
	if [ -n "$ONION" ]; then
		note "tor:           the NOX onion service is published; devices reach the server through it away from home"
	elif [ "$OPT_NO_TOR" = 1 ]; then
		note "tor:           not set up (--no-tor); devices connect directly only"
	else
		note "tor:           not set up - $TOR_PROBLEM"
		note "               devices connect directly only; see deploy/README.md to set tor up by hand"
	fi
	note "server log:    $SERVER_LOG"
	say_after_restart "$NOXD_CMD"
	firewall_hint
}

main() {
	local lowest
	parse_options "$@"
	if [ -z "$OPT_PREFIX" ]; then
		[ "$(uname -s)" = Linux ] || die "this script is for Linux; on macOS use install-macos.sh, on Windows install-windows.ps1"
		[ "$(id -u)" = 0 ] || die "installing needs administrator rights: run it with sudo, as sudo $0"
		command -v systemctl >/dev/null 2>&1 || die "this script sets the server up as a systemd service, and there is no systemctl here"
		[ -z "$OPT_TOR_BIN" ] || die "--tor-bin is for a check with --prefix; an installation uses the system's tor"
	fi
	command -v curl >/dev/null 2>&1 || die "curl is needed (to talk to the server's service page): install it and run the script again"
	set_paths
	detect_install
	arm_traps
	make_work

	step "Checking this machine"
	lowest=$(unprivileged_port_start)
	refuse_low_port "$PORT" "$lowest" --port
	refuse_low_port "$STATUS_PORT" "$lowest" --status-port
	check_ports
	if [ "$UPDATE" = 1 ]; then
		note "a NOX server is installed here: this run updates it, and leaves its data, password and onion address alone"
	fi
	prepare_binary
	if [ "$FRESH_DATA" = 1 ]; then
		ask_password
		if [ -z "$PUBLIC_ADDR" ]; then
			ask_public_addr
		fi
	fi

	# From here on the machine changes; a failure takes every change back.
	install_layout
	install_binary
	if [ "$OPT_NO_TOR" = 0 ]; then
		UNDO_INTO=TOR
		if setup_tor; then
			undo_keep_tor
		else
			UNDO_INTO=MAIN
			warn "tor: $TOR_PROBLEM"
			undo_run TOR
			ONION=""
			say "The server is installed without tor: devices connect directly."
		fi
	fi
	start_server
	local state
	if ! state=$(wait_health); then
		say "The end of the server's log:" >&2
		server_log_tail >&2
		die "the server did not start, or did not answer on its service page within $NOX_HEALTH_WAIT seconds"
	fi
	COMMITTED=1
	note "the server answers: $state"

	if [ "$FRESH_DATA" = 1 ]; then
		finish_new "$NOXD_CMD" || true
	else
		say ""
		say "The server was updated and restarted. It is locked until its password is entered:"
		say "on the service page, http://127.0.0.1:$STATUS_PORT, or with: $NOXD_CMD unlock$(status_flag)"
	fi
	summary
}

main "$@"
