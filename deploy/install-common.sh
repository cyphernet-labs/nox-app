# shellcheck shell=bash
# The variables set here are read by the scripts that source this file, and
# PORT, STATUS_PORT, UPDATE, REPO_DIR, NOXD, RUN_DIR and SERVER_LOG are set by
# them.
# shellcheck disable=SC2034,SC2153
#
# Shared by install-macos.sh and install-linux.sh: sourced by them, never run
# on its own. Written for bash 3.2, the bash macOS ships: no associative
# arrays, no namerefs, no ${var,,}, and an empty array is never expanded bare
# under `set -u`.
#
# What lives here is everything the two systems do the same way: the options,
# the checks before anything changes, the binary, the password, the addresses,
# the templates, the record of changes that a failed run undoes, the wait for
# the service page, the first password and the link.
#
# Secrets: the password lives in one shell variable, NOX_PASSWORD, never
# exported, and goes to `noxd unlock` on its standard input - never on a command
# line, never into a file. The pairing link is printed by `noxd link` straight
# to the terminal and is never held by the script.

# The NOX server's port, and the service page's (loopback only).
NOX_DEFAULT_PORT=8443
NOX_DEFAULT_STATUS_PORT=8081

# tor older than 0.4.9 is refused by the Tor network since 2026-09-01.
NOX_TOR_MIN_VERSION=0.4.9

# How long to wait for the service page and for tor's onion address.
NOX_HEALTH_WAIT=60
NOX_ONION_WAIT=60

# --- output ------------------------------------------------------------------

say() { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

# q quotes one word for the undo record, which is read back by eval.
q() { printf '%q' "$1"; }

# torq escapes a value for a quoted torrc string: tor reads C escapes there.
torq() {
	local v=$1
	v=${v//\\/\\\\}
	v=${v//\"/\\\"}
	printf '%s' "$v"
}

# xml escapes a value for a plist. (sed, not ${v//&/...}: from bash 5.2 an &
# in that replacement stands for the matched text.)
xml() {
	printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# --- options -----------------------------------------------------------------

OPT_PORT=""
OPT_STATUS_PORT=""
OPT_BINARY=""
OPT_PUBLIC_ADDR=""
OPT_NO_TOR=0
OPT_TOR_BIN=""
OPT_PREFIX=""
OPT_NO_SERVICE=0

# parse_options reads the options both scripts take. Anything else is an
# error: an option silently ignored is a setting the owner believes in.
parse_options() {
	while [ $# -gt 0 ]; do
		case $1 in
		--port) need_value "$@" && OPT_PORT=$2 && shift 2 ;;
		--port=*) OPT_PORT=${1#*=} && shift ;;
		--status-port) need_value "$@" && OPT_STATUS_PORT=$2 && shift 2 ;;
		--status-port=*) OPT_STATUS_PORT=${1#*=} && shift ;;
		--binary) need_value "$@" && OPT_BINARY=$2 && shift 2 ;;
		--binary=*) OPT_BINARY=${1#*=} && shift ;;
		--public-addr) need_value "$@" && OPT_PUBLIC_ADDR=$2 && shift 2 ;;
		--public-addr=*) OPT_PUBLIC_ADDR=${1#*=} && shift ;;
		--no-tor) OPT_NO_TOR=1 && shift ;;
		--tor-bin) need_value "$@" && OPT_TOR_BIN=$2 && shift 2 ;;
		--tor-bin=*) OPT_TOR_BIN=${1#*=} && shift ;;
		--prefix) need_value "$@" && OPT_PREFIX=$2 && shift 2 ;;
		--prefix=*) OPT_PREFIX=${1#*=} && shift ;;
		--no-service) OPT_NO_SERVICE=1 && shift ;;
		-h | --help)
			usage
			exit 0
			;;
		*) die "unknown option: $1 (see --help)" ;;
		esac
	done

	if [ -n "$OPT_PORT" ]; then
		valid_port "$OPT_PORT" || die "--port takes a port number, 1-65535: $OPT_PORT"
	fi
	if [ -n "$OPT_STATUS_PORT" ]; then
		valid_port "$OPT_STATUS_PORT" || die "--status-port takes a port number, 1-65535: $OPT_STATUS_PORT"
	fi
	if [ -n "$OPT_PUBLIC_ADDR" ]; then
		valid_public_addr "$OPT_PUBLIC_ADDR" || die "--public-addr takes host:port, such as nox.example.org:8443: $OPT_PUBLIC_ADDR"
	fi
	if [ -n "$OPT_BINARY" ]; then
		[ -f "$OPT_BINARY" ] || die "--binary: no file at $OPT_BINARY"
		OPT_BINARY=$(absolute "$OPT_BINARY")
	fi
	if [ -n "$OPT_TOR_BIN" ]; then
		[ -f "$OPT_TOR_BIN" ] || die "--tor-bin: no file at $OPT_TOR_BIN"
		OPT_TOR_BIN=$(absolute "$OPT_TOR_BIN")
	fi
	if [ -n "$OPT_TOR_BIN" ] && [ "$OPT_NO_TOR" = 1 ]; then
		die "--tor-bin and --no-tor contradict each other"
	fi
	# A check without changing the system is both at once: every file under
	# the prefix, and no service the system would go on running from there.
	if [ -n "$OPT_PREFIX" ] && [ "$OPT_NO_SERVICE" = 0 ]; then
		die "--prefix goes together with --no-service: services must not run from a scratch directory"
	fi
	if [ "$OPT_NO_SERVICE" = 1 ] && [ -z "$OPT_PREFIX" ]; then
		die "--no-service goes together with --prefix DIR: it is for checking the script without changing the system"
	fi
	if [ -n "$OPT_PREFIX" ]; then
		mkdir -p "$OPT_PREFIX" || die "cannot create the prefix $OPT_PREFIX"
		OPT_PREFIX=$(cd "$OPT_PREFIX" && pwd -P)
	fi
	return 0
}

need_value() {
	[ $# -ge 2 ] || die "$1 needs a value"
	case $2 in
	--*) die "$1 needs a value, not $2" ;;
	esac
	return 0
}

absolute() {
	local dir base
	dir=$(cd "$(dirname "$1")" && pwd -P) || return 1
	base=$(basename "$1")
	printf '%s/%s' "$dir" "$base"
}

valid_port() {
	case $1 in
	'' | *[!0-9]*) return 1 ;;
	esac
	[ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

# valid_public_addr takes host:port - a name, an IPv4 address or [IPv6] - and
# not an onion address, which tor gives the server itself. The server checks
# again when it applies it; this check only stops a typo before it is written
# into the service.
valid_public_addr() {
	local addr=$1
	case $addr in
	*.onion | *.onion:*) return 1 ;;
	esac
	[[ $addr =~ ^([A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?|\[[0-9A-Fa-f:.]+\]):([0-9]{1,5})$ ]] || return 1
	valid_port "${BASH_REMATCH[3]}"
}

valid_onion() {
	[[ $1 =~ ^[a-z2-7]{56}\.onion$ ]]
}

# --- the record of changes ---------------------------------------------------
#
# Every change to the machine pushes the command that takes it back. A run that
# fails before the server answers runs them, newest first, and the machine is
# as it was. The tor steps keep a record of their own: tor failing takes back
# only tor, and the server is installed without it.

UNDO_MAIN=()
UNDO_TOR=()
UNDO_INTO=MAIN
# COMMITTED is set once the server answers on its service page: from there on
# the installation stands, and what fails after it is reported, not undone.
COMMITTED=0

undo_push() {
	if [ "$UNDO_INTO" = TOR ]; then
		UNDO_TOR[${#UNDO_TOR[@]}]=$1
	else
		UNDO_MAIN[${#UNDO_MAIN[@]}]=$1
	fi
}

# undo_run MAIN|TOR runs that record newest first and empties it.
undo_run() {
	local name="UNDO_$1" count i cmd
	eval "count=\${#${name}[@]}"
	i=$((count - 1))
	while [ "$i" -ge 0 ]; do
		eval "cmd=\${${name}[$i]}"
		eval "$cmd" || warn "could not undo: $cmd"
		i=$((i - 1))
	done
	eval "$name=()"
}

# undo_keep_tor moves the tor record into the main one: tor is in place, and
# from here on only a failure of the whole run takes it back.
undo_keep_tor() {
	local i=0
	while [ "$i" -lt ${#UNDO_TOR[@]} ]; do
		UNDO_MAIN[${#UNDO_MAIN[@]}]=${UNDO_TOR[$i]}
		i=$((i + 1))
	done
	UNDO_TOR=()
	UNDO_INTO=MAIN
}

WORK=""

on_exit() {
	local status=$?
	if [ -t 0 ]; then
		stty echo 2>/dev/null || true
	fi
	if [ "$status" -ne 0 ] && [ "$COMMITTED" = 0 ]; then
		if [ ${#UNDO_TOR[@]} -gt 0 ] || [ ${#UNDO_MAIN[@]} -gt 0 ]; then
			printf '\n' >&2
			warn "the installation did not finish; taking back what this run changed"
			undo_run TOR
			undo_run MAIN
			say "This machine is as it was before the run."
		fi
	fi
	if [ -n "$WORK" ] && [ -d "$WORK" ]; then
		rm -rf "$WORK"
	fi
	exit "$status"
}

arm_traps() {
	trap on_exit EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
}

# make_work creates the run's scratch directory: under the prefix when
# checking, so nothing is written outside it, and in TMPDIR otherwise.
make_work() {
	local base=${TMPDIR:-/tmp}
	if [ -n "$OPT_PREFIX" ]; then
		base=$OPT_PREFIX
	fi
	WORK=$(mktemp -d "${base%/}/nox-install.XXXXXX") || die "cannot create a scratch directory in $base"
	chmod 700 "$WORK"
}

# make_dir PATH OWNER GROUP MODE creates a directory that may be shared with
# other software (/usr/local/bin, the logs, the launchd or systemd folders)
# and records how to take it back - the top-most part of it that did not
# exist. One that existed is left exactly as it was. OWNER empty: leave the
# owner alone (a check under a prefix runs as whoever runs it).
make_dir() {
	local path=$1 owner=$2 group=$3 mode=$4 top="" p
	p=$path
	while [ ! -e "$p" ]; do
		top=$p
		p=$(dirname "$p")
	done
	if [ -z "$top" ]; then
		[ -d "$path" ] || die "$path is not a directory"
		return 0
	fi
	mkdir -p "$path" || die "cannot create $path"
	undo_push "rm -rf $(q "$top")"
	if [ -n "$owner" ]; then
		chown "$owner:$group" "$path" || die "cannot give $path to $owner"
	fi
	chmod "$mode" "$path" || die "cannot set the mode of $path"
}

# make_own_dir PATH OWNER GROUP MODE is make_dir for a directory that belongs
# to NOX alone - the server's data, tor's state: its owner and mode are set
# whether it existed or not. Its contents are never touched.
make_own_dir() {
	make_dir "$@"
	if [ -n "$2" ]; then
		chown "$2:$3" "$1" || die "cannot give $1 to $2"
	fi
	chmod "$4" "$1" || die "cannot set the mode of $1"
}

# put_file SRC DEST MODE [OWNER GROUP] installs one file through a rename, so
# a running program never sees half of it, and records how to take it back:
# the previous file is kept in the scratch directory until the run ends.
put_file() {
	local src=$1 dest=$2 mode=$3 owner=${4:-} group=${5:-} keep
	if [ -e "$dest" ]; then
		keep=$(mktemp "$WORK/previous.XXXXXX") || die "cannot keep a copy of $dest"
		cp -p "$dest" "$keep" || die "cannot keep a copy of $dest"
		undo_push "cp -p $(q "$keep") $(q "$dest.nox-undo") && mv -f $(q "$dest.nox-undo") $(q "$dest")"
	else
		undo_push "rm -f $(q "$dest")"
	fi
	cp "$src" "$dest.nox-new" || die "cannot write $dest"
	if [ -n "$owner" ]; then
		chown "$owner:$group" "$dest.nox-new" || die "cannot give $dest to $owner"
	fi
	chmod "$mode" "$dest.nox-new" || die "cannot set the mode of $dest"
	mv -f "$dest.nox-new" "$dest" || die "cannot write $dest"
}

# --- templates ---------------------------------------------------------------

# render TEMPLATE OUT NAME=VALUE... copies TEMPLATE to OUT with every @NAME@
# replaced by VALUE, taken literally. The values reach awk through its
# environment, never its command line, and a placeholder left without a value
# is an error rather than a line written with @NAME@ in it.
render() {
	local template=$1 out=$2 pair names=""
	shift 2
	(
		for pair in "$@"; do
			export "TPL_${pair%%=*}=${pair#*=}"
			names="$names ${pair%%=*}"
		done
		export TPL_NAMES="$names"
		awk '
			BEGIN {
				n = split(ENVIRON["TPL_NAMES"], names, " ")
				for (i = 1; i <= n; i++) known["@" names[i] "@"] = ENVIRON["TPL_" names[i]]
			}
			{
				line = $0
				rest = line
				while (match(rest, /@[A-Z][A-Z_]*@/)) {
					key = substr(rest, RSTART, RLENGTH)
					if (!(key in known)) {
						printf "unfilled placeholder %s in line %d\n", key, NR > "/dev/stderr"
						bad = 1
					}
					rest = substr(rest, RSTART + RLENGTH)
				}
				for (key in known) {
					out = ""
					while ((p = index(line, key)) > 0) {
						out = out substr(line, 1, p - 1) known[key]
						line = substr(line, p + length(key))
					}
					line = out line
				}
				print line
			}
			END { exit bad }
		' "$template"
	) >"$out" || die "cannot render $(basename "$template")"
}

# --- checks ------------------------------------------------------------------

# check_ports refuses a port somebody else listens on - but not, on an
# update, the server's own ports held by its own running server. port_holder
# and own_server_running are the system's: the first names the program
# listening on a port ("another program" when it cannot tell), the second says
# whether the installed server runs.
check_ports() {
	local port holder what
	[ "$PORT" != "$STATUS_PORT" ] || die "--port and --status-port are the same port, $PORT"
	for what in server page; do
		if [ "$what" = server ]; then port=$PORT; else port=$STATUS_PORT; fi
		holder=$(port_holder "$port")
		if [ -z "$holder" ]; then
			continue
		fi
		if [ "$UPDATE" = 1 ] && { [ "$holder" = noxd ] || { [ "$holder" = "another program" ] && own_server_running; }; }; then
			continue
		fi
		if [ "$what" = server ]; then
			die "port $PORT is in use by $holder; pick another with --port"
		fi
		die "port $STATUS_PORT, for the service page, is in use by $holder; pick another with --status-port"
	done
}

# listening_here says whether something accepts connections on a loopback
# port - the check that needs no privileges, beside the system's own.
listening_here() {
	(exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# --- the server binary -------------------------------------------------------

# find_go prints the Go toolchain to build with, or nothing. Under sudo the
# PATH may have lost it, so the usual places and the invoking user's login
# shell are asked too.
find_go() {
	local g
	g=$(command -v go 2>/dev/null || true)
	if [ -z "$g" ]; then
		for g in /usr/local/go/bin/go /opt/homebrew/bin/go /usr/local/bin/go /usr/lib/go/bin/go /snap/bin/go; do
			[ -x "$g" ] && break
			g=""
		done
	fi
	if [ -z "$g" ] && [ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
		g=$(sudo -u "$SUDO_USER" -i sh -c 'command -v go' 2>/dev/null | tail -n 1 || true)
		[ -x "$g" ] || g=""
	fi
	printf '%s' "$g"
}

# prepare_binary sets NEW_BINARY: the noxd given with --binary, or one built
# here from the repository beside this script. Nothing is installed yet.
prepare_binary() {
	local go out src
	if [ -n "$OPT_BINARY" ]; then
		NEW_BINARY=$OPT_BINARY
	else
		src=$REPO_DIR/client_backend
		[ -f "$src/go.mod" ] || die "no server source at $src: run the script from the NOX repository, or pass --binary"
		go=$(find_go)
		[ -n "$go" ] || die "no Go toolchain to build the server with: install Go (see client_backend/go.mod for the version), or pass --binary <a noxd built for this system>"
		step "Building the server"
		mkdir -p "$WORK/build"
		out=$WORK/build/noxd
		if [ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
			# As the person who ran sudo: their module cache, their build
			# cache, and git that trusts their checkout for the version stamp.
			# They may pass through the scratch directory, not read it.
			chmod 711 "$WORK"
			chown "$SUDO_USER" "$WORK/build"
			sudo -u "$SUDO_USER" -H env PATH="$PATH" CGO_ENABLED=0 "$go" -C "$src" build -trimpath -ldflags=-s -o "$out" . ||
				die "the server did not build (see above); fix that, or pass --binary"
		else
			if [ -n "$OPT_PREFIX" ]; then
				# A check writes nowhere but the prefix: the build cache too.
				export GOCACHE="$WORK/gocache"
			fi
			if ! CGO_ENABLED=0 "$go" -C "$src" build -trimpath -ldflags=-s -o "$out" .; then
				# root building somebody else's checkout: git refuses it, and
				# with it the version stamp. Build without the stamp.
				say "Building again without the version stamp."
				CGO_ENABLED=0 "$go" -C "$src" build -buildvcs=false -trimpath -ldflags=-s -o "$out" . ||
					die "the server did not build (see above); fix that, or pass --binary"
			fi
		fi
		NEW_BINARY=$out
	fi
	# It runs here, and it is a server of this generation: the locked start
	# and the commands this script talks to. (-h makes each print its flags
	# and exit non-zero, which is why the output is read and not the status.)
	local help
	help=$("$NEW_BINARY" unlock -h 2>&1 || true)
	case $help in
	*-status-addr*) ;;
	*) die "$NEW_BINARY does not run here as a NOX server with 'noxd unlock'; build it for this system" ;;
	esac
	help=$("$NEW_BINARY" link -h 2>&1 || true)
	case $help in
	*-qr*) ;;
	*) die "$NEW_BINARY has no 'noxd link -qr'; build it from this repository" ;;
	esac
}

# --- the password and the public address -------------------------------------

NOX_PASSWORD=""

# password_refusal prints why the server would refuse pw as its first password,
# in the server's words, or nothing. The rule is the server's: at least twelve
# characters - characters, not bytes - and not whitespace alone. The server
# checks again; this only spares a round trip.
password_refusal() {
	local pw=$1 chars
	case $pw in
	*[![:space:]]*) ;;
	*)
		printf 'Use at least 12 characters.'
		return 0
		;;
	esac
	# UTF-8 continuation bytes are the ones that do not start a character.
	chars=$(printf '%s' "$pw" | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' ')
	if [ "$chars" -lt 12 ]; then
		printf 'Use at least 12 characters.'
	fi
}

# read_secret LABEL VAR reads one line from the terminal into VAR without
# echo. Echo goes off BEFORE the label is shown: `read -s` shows its prompt
# first, and whatever is typed - or pasted - in that instant is echoed.
read_secret() {
	local line status
	stty -echo 2>/dev/null || true
	printf '%s' "$1" >&2
	IFS= read -r line
	status=$?
	stty echo 2>/dev/null || true
	printf '\n' >&2
	printf -v "$2" '%s' "$line"
	return "$status"
}

# ask_password sets NOX_PASSWORD: asked twice at a terminal, without echo,
# until both match and the server would take it; or two lines on standard
# input when that is not a terminal - the password and its repeat.
ask_password() {
	local pw="" repeat="" refusal
	if [ -t 0 ]; then
		say ""
		say "Set a password for this server. It opens the server's data after every start, and it is stored nowhere."
		say "If you forget this password, the server's data can't be opened by anyone, including you."
		while :; do
			read_secret "Password: " pw || die "no password was given"
			refusal=$(password_refusal "$pw")
			if [ -n "$refusal" ]; then
				say "$refusal"
				continue
			fi
			read_secret "Repeat password: " repeat || die "no password was given"
			if [ "$pw" != "$repeat" ]; then
				say "The passwords don't match."
				continue
			fi
			break
		done
	else
		IFS= read -r pw || [ -n "$pw" ] || die "standard input is not a terminal, so the password is read from it: two lines, the password and its repeat"
		IFS= read -r repeat || [ -n "$repeat" ] || die "standard input ended after the password: its repeat is the second line"
		pw=${pw%$'\r'}
		repeat=${repeat%$'\r'}
		refusal=$(password_refusal "$pw")
		[ -z "$refusal" ] || die "$refusal"
		[ "$pw" = "$repeat" ] || die "The passwords don't match."
	fi
	NOX_PASSWORD=$pw
}

# ask_public_addr sets PUBLIC_ADDR when the owner has one; asked only at a
# terminal, only on a new installation, and only when --public-addr did not
# already say.
ask_public_addr() {
	local addr
	[ -t 0 ] || return 0
	say ""
	say "If this machine is reachable from the internet (a public name or address forwarded to port $PORT),"
	say "enter it as host:port - devices will use it away from home. Otherwise press Enter."
	while :; do
		IFS= read -r -p "Public address: " addr || return 0
		addr=$(printf '%s' "$addr" | tr -d '[:space:]')
		[ -n "$addr" ] || return 0
		if valid_public_addr "$addr"; then
			PUBLIC_ADDR=$addr
			return 0
		fi
		say "That is not host:port (for example nox.example.org:8443). Try again, or press Enter for none."
	done
}

# --- tor ---------------------------------------------------------------------

# tor_version prints the version of the tor at $1 (0.4.9.13), or nothing when
# it does not run.
tor_version() {
	local out
	out=$("$1" --version 2>/dev/null) || true
	printf '%s\n' "$out" | awk '$1 == "Tor" && $2 == "version" { v = $3; sub(/\.$/, "", v); print v; exit }' || true
}

# version_at_least A B: is dotted version A at least B?
version_at_least() {
	awk -v a="$1" -v b="$2" 'BEGIN {
		na = split(a, x, "."); nb = split(b, y, ".")
		n = na > nb ? na : nb
		for (i = 1; i <= n; i++) {
			xi = (i <= na) ? x[i] + 0 : 0; yi = (i <= nb) ? y[i] + 0 : 0
			if (xi > yi) exit 0
			if (xi < yi) exit 1
		}
		exit 0
	}'
}

# tor_unsuitable prints why the tor at $1 cannot carry the NOX onion service,
# or nothing when it can: it runs, it is 0.4.9 or newer, and it was built with
# the proof-of-work module - without it, tor refuses a configuration that
# turns the defence on.
tor_unsuitable() {
	local v modules
	v=$(tor_version "$1")
	if [ -z "$v" ]; then
		printf 'it does not run'
		return 0
	fi
	if ! version_at_least "$v" "$NOX_TOR_MIN_VERSION"; then
		printf 'it is version %s, and the Tor network takes %s or newer' "$v" "$NOX_TOR_MIN_VERSION"
		return 0
	fi
	modules=$("$1" --list-modules 2>/dev/null) || true
	case $modules in
	*"pow: yes"*) ;;
	*) printf 'it was built without proof-of-work support (the "pow" module)' ;;
	esac
}

# wait_onion HS_DIR prints the onion address tor writes there, once it has.
wait_onion() {
	local file="$1/hostname" deadline=$((SECONDS + NOX_ONION_WAIT)) host
	while [ "$SECONDS" -lt "$deadline" ]; do
		if [ -s "$file" ]; then
			host=$(tr -d '[:space:]' <"$file")
			if valid_onion "$host"; then
				printf '%s' "$host"
				return 0
			fi
		fi
		sleep 1
	done
	return 1
}

# --- processes for a check without services ----------------------------------

# bg_start NAME PIDFILE LOG CMD... starts CMD in the background, as a stand-in
# for the service the system would run, and records how to stop it.
bg_start() {
	local name=$1 pidfile=$2 log=$3 pid
	shift 3
	# The mask the services get: what the program creates is its own.
	(
		umask 077
		exec nohup "$@" >>"$log" 2>&1 </dev/null
	) &
	pid=$!
	printf '%s\n' "$pid" >"$pidfile"
	undo_push "bg_stop $(q "$name") $(q "$pidfile")"
}

# bg_running NAME PIDFILE says whether what bg_start started still runs.
bg_running() {
	local pid comm
	[ -f "$2" ] || return 1
	pid=$(cat "$2")
	[ -n "$pid" ] || return 1
	comm=$(ps -p "$pid" -o comm= 2>/dev/null) || return 1
	[ "${comm##*/}" = "$1" ]
}

# bg_stop NAME PIDFILE stops what bg_start started - and only it: the process
# must still be NAME, so a recycled pid is left alone.
bg_stop() {
	local name=$1 pidfile=$2 pid i
	[ -f "$pidfile" ] || return 0
	pid=$(cat "$pidfile")
	if bg_running "$name" "$pidfile"; then
		kill "$pid" 2>/dev/null || true
		i=0
		while [ "$i" -lt 30 ] && kill -0 "$pid" 2>/dev/null; do
			sleep 1
			i=$((i + 1))
		done
		kill -9 "$pid" 2>/dev/null || true
	fi
	rm -f "$pidfile"
}

# --- the running server ------------------------------------------------------

# health prints what the service page says the server is - locked or ok - or
# nothing while it does not answer.
health() {
	local out
	out=$(curl -fsS --noproxy '*' --max-time 3 "http://127.0.0.1:$STATUS_PORT/health" 2>/dev/null) || return 0
	printf '%s\n' "$out" | sed -n 's/.*"status":"\([a-z]*\)".*/\1/p' || true
}

# wait_health prints the server's state once its service page answers. A
# check's server that is gone is not waited for.
wait_health() {
	local deadline=$((SECONDS + NOX_HEALTH_WAIT)) state
	while [ "$SECONDS" -lt "$deadline" ]; do
		state=$(health)
		if [ -n "$state" ]; then
			printf '%s' "$state"
			return 0
		fi
		if [ -n "$OPT_PREFIX" ] && [ -f "$RUN_DIR/noxd.pid" ] && ! kill -0 "$(cat "$RUN_DIR/noxd.pid")" 2>/dev/null; then
			return 1
		fi
		sleep 1
	done
	return 1
}

# set_first_password gives the new server its password through `noxd unlock`
# on standard input. A refusal the script's own check missed is asked again
# at a terminal; anything else is reported with the way to finish by hand.
set_first_password() {
	local out
	while :; do
		if out=$(printf '%s\n%s\n' "$NOX_PASSWORD" "$NOX_PASSWORD" | "$NOXD" unlock -status-addr "127.0.0.1:$STATUS_PORT" 2>&1); then
			NOX_PASSWORD=""
			return 0
		fi
		case $out in
		*"Use at least 12 characters."*)
			if [ -t 0 ]; then
				say "$out"
				ask_password
				continue
			fi
			;;
		esac
		NOX_PASSWORD=""
		warn "the password was not set: $out"
		return 1
	done
}

# wait_open waits for the service page to say ok after the first password.
wait_open() {
	local i=0
	while [ "$i" -lt 30 ]; do
		[ "$(health)" = ok ] && return 0
		sleep 1
		i=$((i + 1))
	done
	return 1
}

# status_flag is what the noxd commands need to find a service page that is
# not on the default port.
status_flag() {
	if [ "$STATUS_PORT" != "$NOX_DEFAULT_STATUS_PORT" ]; then
		printf ' -status-addr 127.0.0.1:%s' "$STATUS_PORT"
	fi
}

# finish_new pairs the first device: the password, then the link and its code.
finish_new() {
	local noxd_cmd=$1
	step "Setting the server's password"
	if ! set_first_password; then
		say ""
		say "The server is installed and running, but has no password yet. Set it on the service page,"
		say "http://127.0.0.1:$STATUS_PORT on this machine, or with: $noxd_cmd unlock$(status_flag)"
		return 1
	fi
	wait_open || warn "the server took the password but has not opened yet; see its log: $SERVER_LOG"
	say "Password set. The server is open."
	step "The link for your first device"
	say "Scan the code with the NOX app on your phone, or paste the link into the app:"
	say ""
	if ! "$NOXD" link -qr -status-addr "127.0.0.1:$STATUS_PORT"; then
		warn "the server did not give a link; get one on the service page or with: $noxd_cmd link -qr$(status_flag)"
	fi
	return 0
}

# say_after_restart is what the owner needs after every restart of the
# machine, and to pair a device later.
say_after_restart() {
	local noxd_cmd=$1
	say ""
	say "After every restart of this machine the server starts locked, and devices cannot connect"
	say "until its password is entered - on the service page, or in a terminal:"
	say "    $noxd_cmd unlock$(status_flag)"
	say "A link lasts 10 minutes. For a new one: Add a device or New link on the service page, or"
	say "    $noxd_cmd link -qr$(status_flag)"
}
