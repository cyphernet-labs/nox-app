#!/bin/bash
#
# Installs the NOX server on macOS, and tor beside it as a service of its own.
#
#   sudo deploy/install-macos.sh [--port 8443] [--public-addr host:port] [--no-tor]
#
# One run does everything: the server's account and folders, the server
# (built from this repository, or --binary), tor from the Tor Project with its
# signature checked, the NOX onion service, both as launchd daemons that start
# with the Mac, the server's password, and at the end the link and QR code
# for the first device. A run on a machine that already has a server updates
# it: the database, the password and the onion address's key are left alone.
#
# Checking the script without changing the system:
#
#   deploy/install-macos.sh --prefix DIR --no-service [--port P --status-port S]
#
# puts every file under DIR, creates no accounts and registers nothing with
# launchd: tor and the server run as background processes of whoever ran it.
#
# Written for /bin/bash 3.2, the bash macOS ships.

set -euo pipefail
# Never traced: a trace prints every expanded word, the password among them.
set +x
umask 022

DEPLOY_DIR=$(cd "$(dirname "$0")" && pwd -P)
REPO_DIR=$(dirname "$DEPLOY_DIR")
# shellcheck source=install-common.sh
. "$DEPLOY_DIR/install-common.sh"

SERVER_LABEL=com.cyphernetlabs.noxd
TOR_LABEL=com.cyphernetlabs.nox-tor
SERVER_ACCOUNT=_nox
TOR_ACCOUNT=_noxtor

# The Tor Expert Bundle: where it is published, how its current version is
# found, and the key its checksums are signed with - Tor Browser Developers
# (signing key) <torbrowser@torproject.org>, by its primary fingerprint. The
# key itself is fetched from the Tor Project's WKD; only this fingerprint is
# trusted, whatever the fetch returns. NOX_TOR_DIST, NOX_TOR_VERSION and
# NOX_TOR_KEY_URL point at a mirror or a local copy (file://).
TOR_SIGNING_KEY=EF6E286DDA85EA2A4BA7DE684E2C6E8793298290
TOR_DIST=${NOX_TOR_DIST:-https://dist.torproject.org/torbrowser}
TOR_VERSION_URL=https://aus1.torproject.org/torbrowser/update_3/release/download-macos.json
TOR_KEY_URL=${NOX_TOR_KEY_URL:-https://openpgpkey.torproject.org/.well-known/openpgpkey/torproject.org/hu/kounek7zrdx745qydx6p59t9mqjpuhdf}

usage() {
	cat <<EOF
Installs the NOX server on this Mac, and tor beside it as a service of its own.

  sudo $0 [options]

Options:
  --port N            the server's port (default $NOX_DEFAULT_PORT; on an update, the one in use)
  --status-port N     the service page's port, on this machine only (default $NOX_DEFAULT_STATUS_PORT)
  --public-addr H:P   the address devices reach this machine at from the internet, if any
  --binary PATH       install this noxd instead of building one (needs no Go)
  --no-tor            no tor: devices connect directly only
  --tor-bin PATH      run this tor (0.4.9 or newer, with proof of work) instead of the
                      Tor Project's, which the script otherwise downloads and checks
  --prefix DIR        check the script without changing the system: every file under DIR,
  --no-service          no accounts, no launchd - give both
  -h, --help          this text

Run again to update: the database, the password and the onion address stay.
EOF
}

# set_paths lays the installation out - under the prefix when checking.
set_paths() {
	ROOT=$OPT_PREFIX
	BIN_DIR="$ROOT/usr/local/bin"
	NOXD="$BIN_DIR/noxd"
	DATA_DIR="$ROOT/Library/Application Support/NOX"
	DB="$DATA_DIR/nox.db"
	LOG_DIR="$ROOT/Library/Logs/NOX"
	SERVER_LOG="$LOG_DIR/noxd.log"
	TOR_LOG="$LOG_DIR/tor.log"
	DAEMONS_DIR="$ROOT/Library/LaunchDaemons"
	SERVER_PLIST="$DAEMONS_DIR/$SERVER_LABEL.plist"
	TOR_PLIST="$DAEMONS_DIR/$TOR_LABEL.plist"
	TOR_HOME="$ROOT/usr/local/libexec/nox-tor"
	TOR_ETC="$ROOT/usr/local/etc/nox-tor"
	TORRC="$TOR_ETC/torrc"
	TOR_DEFAULTS="$TOR_ETC/torrc-defaults"
	NOX_TOR_CONF="$TOR_ETC/nox-tor.conf"
	TOR_DATA="$ROOT/usr/local/var/lib/nox-tor"
	HS_DIR="$TOR_DATA/nox"
	RUN_DIR="$ROOT/usr/local/var/run/nox"
	if [ -n "$OPT_PREFIX" ]; then
		SERVER_USER=$(id -un)
		SERVER_GROUP=$(id -gn)
		TOR_USER=$SERVER_USER
		TOR_GROUP=$SERVER_GROUP
		NOXD_CMD=$NOXD
	else
		SERVER_USER=$SERVER_ACCOUNT
		SERVER_GROUP=$SERVER_ACCOUNT
		TOR_USER=$TOR_ACCOUNT
		TOR_GROUP=$TOR_ACCOUNT
		NOXD_CMD=noxd
	fi
}

# previous_arg FLAG prints the value that follows FLAG in the installed
# server's job, or nothing.
previous_arg() {
	local out
	[ -f "$SERVER_PLIST" ] || return 0
	out=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments' "$SERVER_PLIST" 2>/dev/null) || return 0
	printf '%s\n' "$out" | awk -v flag="$1" '{ gsub(/^[ \t]+|[ \t]+$/, "") } prev == flag { print; exit } { prev = $0 }' || true
}

# detect_install reads what is already here. UPDATE: a server was installed
# before. FRESH_DATA: there is no database and no key yet - the password is
# set by this run. The ports and the public address default to what the
# installed server uses.
detect_install() {
	local prev
	UPDATE=0
	FRESH_DATA=1
	if [ -e "$DB" ] || [ -e "$DB.key" ]; then
		FRESH_DATA=0
		UPDATE=1
	fi
	if [ -f "$SERVER_PLIST" ]; then
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
	local out name
	out=$(lsof -nP -iTCP:"$1" -sTCP:LISTEN -Fc 2>/dev/null) || true
	name=$(printf '%s\n' "$out" | sed -n 's/^c//p' | head -n 1) || true
	if [ -z "$name" ] && listening_here "$1"; then
		name="another program"
	fi
	printf '%s' "$name"
}

own_server_running() {
	if [ -n "$OPT_PREFIX" ]; then
		bg_running noxd "$RUN_DIR/noxd.pid"
	else
		launchctl print "system/$SERVER_LABEL" >/dev/null 2>&1
	fi
}

# --- accounts and folders ----------------------------------------------------

# free_system_id prints an id below 500 that no account and no group uses.
free_system_id() {
	local used id
	used=$({
		dscl . -list /Users UniqueID
		dscl . -list /Groups PrimaryGroupID
	} | awk '{ print $2 }')
	# Matched as whole lines of one string, not through a pipe: grep -q leaving
	# early would fail the pipe, and the id would read as free.
	used="
$used
"
	id=499
	while [ "$id" -ge 300 ]; do
		case $used in
		*"
$id
"*) ;;
		*)
			printf '%s' "$id"
			return 0
			;;
		esac
		id=$((id - 1))
	done
	return 1
}

# ensure_account NAME DESCRIPTION creates a hidden role account with its own
# group, unless it exists: no home, no shell, no password.
ensure_account() {
	local name=$1 desc=$2 id gid
	if dscl . -read "/Users/$name" UniqueID >/dev/null 2>&1; then
		return 0
	fi
	id=$(free_system_id) || die "no free account id below 500 for $name"
	if ! dscl . -read "/Groups/$name" PrimaryGroupID >/dev/null 2>&1; then
		dscl . -create "/Groups/$name" || die "cannot create the group $name"
		undo_push "dscl . -delete $(q "/Groups/$name")"
		dscl . -create "/Groups/$name" PrimaryGroupID "$id"
		dscl . -create "/Groups/$name" RealName "$desc"
		dscl . -create "/Groups/$name" Password '*'
	fi
	gid=$(dscl . -read "/Groups/$name" PrimaryGroupID | awk '{ print $2 }')
	dscl . -create "/Users/$name" || die "cannot create the account $name"
	undo_push "dscl . -delete $(q "/Users/$name")"
	dscl . -create "/Users/$name" UniqueID "$id"
	dscl . -create "/Users/$name" PrimaryGroupID "$gid"
	dscl . -create "/Users/$name" UserShell /usr/bin/false
	dscl . -create "/Users/$name" NFSHomeDirectory /var/empty
	dscl . -create "/Users/$name" RealName "$desc"
	dscl . -create "/Users/$name" Password '*'
	note "account $name created"
}

# ensure_log FILE OWNER GROUP creates a log file the job's account can write.
ensure_log() {
	if [ ! -e "$1" ]; then
		: >"$1" || die "cannot create $1"
		undo_push "rm -f $(q "$1")"
	fi
	if [ -z "$OPT_PREFIX" ]; then
		chown "$2:$3" "$1"
	fi
	chmod 640 "$1"
}

install_layout() {
	local owner=root group=wheel
	if [ -n "$OPT_PREFIX" ]; then
		owner=""
		group=""
	else
		step "Accounts and folders"
		ensure_account "$SERVER_ACCOUNT" "NOX server"
	fi
	make_dir "$BIN_DIR" "$owner" "$group" 755
	make_dir "$DAEMONS_DIR" "$owner" "$group" 755
	make_dir "$LOG_DIR" "$owner" "$group" 755
	if [ -n "$OPT_PREFIX" ]; then
		make_own_dir "$DATA_DIR" "" "" 700
		make_dir "$RUN_DIR" "" "" 755
	else
		make_own_dir "$DATA_DIR" "$SERVER_ACCOUNT" "$SERVER_ACCOUNT" 700
	fi
	ensure_log "$SERVER_LOG" "$SERVER_USER" "$SERVER_GROUP"
}

install_binary() {
	step "Installing the server at $NOXD"
	if [ -n "$OPT_PREFIX" ]; then
		put_file "$NEW_BINARY" "$NOXD" 755
	else
		put_file "$NEW_BINARY" "$NOXD" 755 root wheel
	fi
	# A binary carried over from another Mac may come quarantined, and
	# launchd would not start it.
	xattr -d com.apple.quarantine "$NOXD" 2>/dev/null || true
}

# --- launchd -----------------------------------------------------------------

job_loaded() {
	launchctl print "system/$1" >/dev/null 2>&1
}

# job_install LABEL RENDERED_PLIST DEST starts a launchd daemon from a fresh
# plist, replacing the one that ran before, and records how to bring the old
# one back.
job_install() {
	local label=$1 rendered=$2 dest=$3
	if job_loaded "$label"; then
		launchctl bootout "system/$label" 2>/dev/null || die "cannot stop $label"
		# Runs last when undoing: the old plist is back by then.
		undo_push "launchctl bootstrap system $(q "$dest")"
	fi
	put_file "$rendered" "$dest" 644 root wheel
	launchctl enable "system/$label" 2>/dev/null || true
	launchctl bootstrap system "$dest" || die "launchd did not start $label"
	undo_push "launchctl bootout system/$label 2>/dev/null || true"
}

# --- tor ---------------------------------------------------------------------

TOR_PROBLEM=""
ONION=""

tor_fail() {
	TOR_PROBLEM=$1
	return 1
}

# find_gpg prints a program that checks OpenPGP signatures - gpgv, which needs
# no keyring directory and no agent, or else gpg - or nothing.
find_gpg() {
	local g name dir
	for name in gpgv gpgv2 gpg gpg2; do
		g=$(command -v "$name" 2>/dev/null || true)
		if [ -z "$g" ]; then
			for dir in /opt/homebrew/bin /usr/local/bin /usr/local/MacGPG2/bin; do
				if [ -x "$dir/$name" ]; then
					g=$dir/$name
					break
				fi
			done
		fi
		if [ -n "$g" ]; then
			printf '%s' "$g"
			return 0
		fi
	done
}

# signed_by_tor_project SIG DATA KEYRING succeeds only when SIG is a valid
# signature over DATA by a key whose PRIMARY fingerprint is the pinned one.
# The verdict is read from the status lines, not the exit code: gpg without
# an agent fails on the way out after checking perfectly well.
signed_by_tor_project() {
	local sig=$1 data=$2 keyring=$3 checker status home
	checker=$(find_gpg)
	case ${checker##*/} in
	gpgv*)
		status=$("$checker" --keyring "$keyring" --status-fd 1 "$sig" "$data" 2>/dev/null) || true
		;;
	*)
		home=$(mktemp -d "$WORK/gnupg.XXXXXX")
		chmod 700 "$home"
		status=$("$checker" --homedir "$home" --batch --no-autostart --no-default-keyring --keyring "$keyring" \
			--trust-model always --status-fd 1 --verify "$sig" "$data" 2>/dev/null) || true
		;;
	esac
	printf '%s\n' "$status" | awk -v fpr="$TOR_SIGNING_KEY" '
		$1 == "[GNUPG:]" && $2 == "VALIDSIG" && $NF == fpr { ok = 1 }
		$1 == "[GNUPG:]" && ($2 == "BADSIG" || $2 == "ERRSIG" || $2 == "REVKEYSIG") { bad = 1 }
		END { exit !(ok && !bad) }'
}

# gpg_dearmor IN OUT turns an armoured key into a binary one, with gpg.
gpg_dearmor() {
	local g home
	g=$(command -v gpg 2>/dev/null || true)
	[ -n "$g" ] || return 1
	home=$(mktemp -d "$WORK/gnupg.XXXXXX")
	chmod 700 "$home"
	"$g" --homedir "$home" --batch --no-autostart --dearmor <"$1" >"$2" 2>/dev/null
}

fetch() {
	curl -fsSL --proto '=https,file' --retry 2 --connect-timeout 30 --max-time 900 -o "$2" "$1"
}

# download_tor_bundle fetches the Tor Expert Bundle for this Mac into DIR and
# checks it: the checksum list must carry a valid signature by the Tor Browser
# signing key - its primary fingerprint, not just any key that answers to the
# name - and the bundle must match its line in the list. Then it is unpacked
# and signed ad hoc, without which Apple Silicon kills it at launch.
download_tor_bundle() {
	local dir=$1 arch version tarball keyring expected actual
	[ -n "$(find_gpg)" ] || tor_fail "there is no gpg to check the Tor Project's signature with (brew install gnupg, or GPG Suite), and tor is never installed unchecked" || return 1
	arch=x86_64
	if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ]; then
		arch=aarch64
	fi
	version=${NOX_TOR_VERSION:-}
	if [ -z "$version" ]; then
		version=$(curl -fsSL --proto '=https' --connect-timeout 30 --max-time 60 "$TOR_VERSION_URL" 2>/dev/null |
			sed -n 's/.*"version"[^"]*"\([0-9][0-9.]*\)".*/\1/p' | head -n 1) || true
	fi
	[[ $version =~ ^[0-9]+(\.[0-9]+)+$ ]] || tor_fail "could not learn the current Tor Expert Bundle version from the Tor Project (no network?)" || return 1
	tarball="tor-expert-bundle-macos-$arch-$version.tar.gz"
	note "downloading $tarball"
	mkdir -p "$dir/download" "$dir/bundle"
	fetch "$TOR_DIST/$version/$tarball" "$dir/download/$tarball" &&
		fetch "$TOR_DIST/$version/sha256sums-signed-build.txt" "$dir/download/sums.txt" &&
		fetch "$TOR_DIST/$version/sha256sums-signed-build.txt.asc" "$dir/download/sums.txt.asc" &&
		fetch "$TOR_KEY_URL" "$dir/download/signing-key" ||
		tor_fail "could not download the Tor Expert Bundle $version (no network?)" || return 1

	note "checking the Tor Project's signature"
	keyring=$dir/download/signing-key
	if grep -q -e '-----BEGIN PGP' "$keyring"; then
		# gpgv reads binary keys only; an armoured one (a key file from a
		# mirror) is unwrapped first.
		gpg_dearmor "$keyring" "$keyring.bin" || tor_fail "the Tor Project's signing key could not be read" || return 1
		keyring=$keyring.bin
	fi
	signed_by_tor_project "$dir/download/sums.txt.asc" "$dir/download/sums.txt" "$keyring" ||
		tor_fail "the checksum list is not signed by the Tor Project's key ($TOR_SIGNING_KEY); tor was not installed" || return 1
	expected=$(awk -v f="$tarball" '$2 == f { print $1; exit }' "$dir/download/sums.txt")
	actual=$(shasum -a 256 "$dir/download/$tarball" | awk '{ print $1 }')
	[ -n "$expected" ] && [ "$expected" = "$actual" ] ||
		tor_fail "the downloaded $tarball does not match its signed checksum; tor was not installed" || return 1
	note "signature and checksum match"

	tar -xzf "$dir/download/$tarball" -C "$dir/bundle" || tor_fail "could not unpack $tarball" || return 1
	[ -f "$dir/bundle/tor/tor" ] || tor_fail "$tarball holds no tor/tor" || return 1
	codesign --force -s - "$dir/bundle/tor/tor" "$dir"/bundle/tor/*.dylib >/dev/null 2>&1 ||
		tor_fail "could not sign tor for this Mac (codesign)" || return 1
	return 0
}

# choose_tor sets TOR_EXE: the tor given with --tor-bin, the Tor Project's this
# script installed before, or a fresh Tor Expert Bundle - in that order, each
# taken only if it can carry the onion service.
choose_tor() {
	local why
	TOR_FRESH=""
	if [ -n "$OPT_TOR_BIN" ]; then
		why=$(tor_unsuitable "$OPT_TOR_BIN")
		[ -z "$why" ] || tor_fail "the tor at $OPT_TOR_BIN cannot be used: $why" || return 1
		TOR_EXE=$OPT_TOR_BIN
		note "using the tor at $TOR_EXE ($(tor_version "$TOR_EXE"))"
		return 0
	fi
	if [ -x "$TOR_HOME/tor" ] && [ -z "$(tor_unsuitable "$TOR_HOME/tor")" ]; then
		TOR_EXE=$TOR_HOME/tor
		note "using the tor installed before ($(tor_version "$TOR_EXE"))"
		return 0
	fi
	download_tor_bundle "$WORK/tor" || return 1
	why=$(tor_unsuitable "$WORK/tor/bundle/tor/tor")
	[ -z "$why" ] || tor_fail "the downloaded tor cannot be used: $why" || return 1
	TOR_FRESH=$WORK/tor/bundle/tor
	TOR_EXE=$TOR_HOME/tor
	note "Tor Expert Bundle ready ($(tor_version "$TOR_FRESH/tor"))"
}

# setup_tor installs tor and the NOX onion service and sets ONION. Every
# change it makes goes on the tor record: on failure it returns 1 with
# TOR_PROBLEM set, and the caller takes back tor alone.
setup_tor() {
	local owner=root group=wheel f
	step "tor"
	choose_tor || return 1
	if [ -n "$OPT_PREFIX" ]; then
		owner=""
		group=""
	else
		ensure_account "$TOR_ACCOUNT" "tor for NOX"
	fi
	if [ -n "$TOR_FRESH" ]; then
		make_dir "$TOR_HOME" "$owner" "$group" 755
		for f in "$TOR_FRESH"/tor "$TOR_FRESH"/*.dylib; do
			[ -f "$f" ] || continue
			put_file "$f" "$TOR_HOME/$(basename "$f")" 755 "$owner" "$group"
		done
	fi
	make_dir "$TOR_ETC" "$owner" "$group" 755
	if [ -n "$OPT_PREFIX" ]; then
		make_own_dir "$TOR_DATA" "" "" 700
	else
		make_own_dir "$TOR_DATA" "$TOR_ACCOUNT" "$TOR_ACCOUNT" 700
	fi
	ensure_log "$TOR_LOG" "$TOR_USER" "$TOR_GROUP"

	# tor's own settings are written once and then belong to the owner; the
	# NOX onion service is written on every run.
	if [ ! -e "$TORRC" ]; then
		render "$DEPLOY_DIR/torrc.tmpl" "$WORK/torrc" DATA_DIR="$(torq "$TOR_DATA")" LOG_TARGET=stdout NOX_CONF="$(torq "$NOX_TOR_CONF")"
		put_file "$WORK/torrc" "$TORRC" 644 "$owner" "$group"
	fi
	if [ ! -e "$TOR_DEFAULTS" ]; then
		: >"$WORK/torrc-defaults"
		put_file "$WORK/torrc-defaults" "$TOR_DEFAULTS" 644 "$owner" "$group"
	fi
	render "$DEPLOY_DIR/nox-tor.conf.tmpl" "$WORK/nox-tor.conf" HS_DIR="$(torq "$HS_DIR")" PORT="$PORT"
	put_file "$WORK/nox-tor.conf" "$NOX_TOR_CONF" 644 "$owner" "$group"

	if ! tor_check_config; then
		tor_fail "tor does not accept its settings: $TOR_CHECK" || return 1
	fi
	# tor writes the address from the key on every start; without the old
	# file, the wait below proves this start. The key itself stays.
	rm -f "$HS_DIR/hostname"

	if [ -n "$OPT_PREFIX" ]; then
		bg_stop tor "$RUN_DIR/nox-tor.pid"
		bg_start tor "$RUN_DIR/nox-tor.pid" "$TOR_LOG" "$TOR_EXE" --defaults-torrc "$TOR_DEFAULTS" -f "$TORRC"
		render_tor_job "$WORK/tor.plist"
		put_file "$WORK/tor.plist" "$TOR_PLIST" 644
	else
		render_tor_job "$WORK/tor.plist"
		job_install "$TOR_LABEL" "$WORK/tor.plist" "$TOR_PLIST"
	fi
	if ! ONION=$(wait_onion "$HS_DIR"); then
		# Shown now: taking tor back removes a log this run created.
		say "The end of tor's log:" >&2
		tail -n 8 "$TOR_LOG" >&2 2>/dev/null || true
		tor_fail "tor did not write its onion address within $NOX_ONION_WAIT seconds" || return 1
	fi
	note "the onion service is ready"
	return 0
}

TOR_CHECK=""

# tor_check_config runs tor's own check of the settings, as the account tor
# runs as - tor refuses a data directory another account owns.
tor_check_config() {
	local out
	if [ -n "$OPT_PREFIX" ]; then
		out=$("$TOR_EXE" --defaults-torrc "$TOR_DEFAULTS" -f "$TORRC" --verify-config 2>&1) && return 0
	else
		out=$(sudo -u "$TOR_ACCOUNT" "$TOR_EXE" --defaults-torrc "$TOR_DEFAULTS" -f "$TORRC" --verify-config 2>&1) && return 0
	fi
	TOR_CHECK=$(printf '%s\n' "$out" | grep -E '\[(warn|err)\]' | tail -n 3 | sed 's/^.*\] //' | tr '\n' ' ') || true
	[ -n "$TOR_CHECK" ] || TOR_CHECK=$(printf '%s\n' "$out" | tail -n 1)
	return 1
}

render_tor_job() {
	render "$DEPLOY_DIR/$TOR_LABEL.plist.tmpl" "$1" \
		LABEL="$TOR_LABEL" TOR="$(xml "$TOR_EXE")" TOR_DEFAULTS="$(xml "$TOR_DEFAULTS")" TORRC="$(xml "$TORRC")" \
		USER="$TOR_USER" GROUP="$TOR_GROUP" LOG="$(xml "$TOR_LOG")"
	plutil -lint -s "$1" || die "the rendered tor job is not a valid plist"
}

# --- the server --------------------------------------------------------------

# address_plist_args is the part of the job's arguments that carries the
# addresses, one <string> per line, each line ending the way the template
# expects.
address_plist_args() {
	local tab
	tab=$(printf '\t\t')
	if [ -n "$ONION" ]; then
		printf '%s<string>-onion-addr</string>\n%s<string>%s</string>\n' "$tab" "$tab" "$ONION"
	fi
	if [ -n "$PUBLIC_ADDR" ]; then
		printf '%s<string>-public-addr</string>\n%s<string>%s</string>\n' "$tab" "$tab" "$(xml "$PUBLIC_ADDR")"
	fi
}

start_server() {
	local args address_args
	step "Starting the server"
	# The template puts </array> right after the value: a value that is not
	# empty ends with its own line break.
	address_args=$(address_plist_args)
	if [ -n "$address_args" ]; then
		address_args="$address_args"$'\n'
	fi
	render "$DEPLOY_DIR/$SERVER_LABEL.plist.tmpl" "$WORK/noxd.plist" \
		LABEL="$SERVER_LABEL" NOXD="$(xml "$NOXD")" PORT="$PORT" DB="$(xml "$DB")" STATUS_PORT="$STATUS_PORT" \
		ADDRESS_ARGS="$address_args" USER="$SERVER_USER" GROUP="$SERVER_GROUP" \
		DATA_DIR="$(xml "$DATA_DIR")" LOG="$(xml "$SERVER_LOG")"
	plutil -lint -s "$WORK/noxd.plist" || die "the rendered server job is not a valid plist"
	if [ -n "$OPT_PREFIX" ]; then
		bg_stop noxd "$RUN_DIR/noxd.pid"
		put_file "$WORK/noxd.plist" "$SERVER_PLIST" 644
		set -- -addr "0.0.0.0:$PORT" -db "$DB" -status-addr "127.0.0.1:$STATUS_PORT"
		if [ -n "$ONION" ]; then set -- "$@" -onion-addr "$ONION"; fi
		if [ -n "$PUBLIC_ADDR" ]; then set -- "$@" -public-addr "$PUBLIC_ADDR"; fi
		args=("$@")
		bg_start noxd "$RUN_DIR/noxd.pid" "$SERVER_LOG" "$NOXD" "${args[@]}"
	else
		job_install "$SERVER_LABEL" "$WORK/noxd.plist" "$SERVER_PLIST"
	fi
}

firewall_hint() {
	local fw=/usr/libexec/ApplicationFirewall/socketfilterfw state
	[ -z "$OPT_PREFIX" ] && [ -x "$fw" ] || return 0
	state=$("$fw" --getglobalstate 2>/dev/null) || return 0
	case $state in
	*enabled* | *"State = 1"* | *"State = 2"*)
		say ""
		say "The macOS firewall is on. If phones on your network cannot connect, allow incoming connections for"
		say "$NOXD: System Settings > Network > Firewall > Options, or"
		say "    sudo $fw --add $NOXD --unblockapp $NOXD"
		;;
	esac
}

summary() {
	step "Done"
	if [ -n "$OPT_PREFIX" ]; then
		say "A check under $OPT_PREFIX: nothing outside it was changed, and nothing starts with the Mac."
		if [ -f "$RUN_DIR/nox-tor.pid" ]; then
			say "The server and tor run as background processes; stop them with"
			say "    kill \$(cat '$RUN_DIR/noxd.pid') \$(cat '$RUN_DIR/nox-tor.pid')"
		else
			say "The server runs as a background process; stop it with"
			say "    kill \$(cat '$RUN_DIR/noxd.pid')"
		fi
	else
		say "The NOX server is installed and starts with this Mac."
	fi
	note "service page:  http://127.0.0.1:$STATUS_PORT (on this machine only)"
	note "server port:   $PORT - devices connect here directly"
	if [ -n "$ONION" ]; then
		note "tor:           running; devices reach the server through it away from home"
	elif [ "$OPT_NO_TOR" = 1 ]; then
		note "tor:           not set up (--no-tor); devices connect directly only"
	else
		note "tor:           not installed - $TOR_PROBLEM"
		note "               devices connect directly only; see deploy/README.md to set tor up by hand"
	fi
	note "logs:          $SERVER_LOG$([ -n "$ONION" ] && printf ', %s' "$TOR_LOG")"
	say_after_restart "$NOXD_CMD"
	firewall_hint
}

main() {
	parse_options "$@"
	[ "$(uname -s)" = Darwin ] || die "this script is for macOS; on Linux use install-linux.sh, on Windows install-windows.ps1"
	if [ -z "$OPT_PREFIX" ] && [ "$(id -u)" != 0 ]; then
		die "installing needs administrator rights: run it with sudo, as sudo $0"
	fi
	set_paths
	detect_install
	arm_traps
	make_work

	step "Checking this Mac"
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
		# Shown now: the rollback removes a log this run created.
		say "The end of the server's log:" >&2
		tail -n 12 "$SERVER_LOG" >&2 2>/dev/null || true
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
