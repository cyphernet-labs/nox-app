# shellcheck shell=bash
# The variables set here are read by the scripts that source this file, and
# PORT, STATUS_PORT, PREV_STATUS_PORT, UPDATE, REPO_DIR, NOXD, NOXD_CMD,
# RUN_DIR, SERVER_LOG, BACKUP_DIR and JOURNAL_DIR are set by them.
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

say() { printf '%s\n' "$*" || output_lost; }
step() { printf '\n==> %s\n' "$*" || output_lost; }
note() { printf '    %s\n' "$*" || output_lost; }
warn() { printf 'warning: %s\n' "$*" >&2 || output_lost; }
die() {
	printf 'error: %s\n' "$*" >&2 || output_lost
	exit 1
}

# output_lost sends all the script prints to /dev/null from here on, once a
# write failed: the terminal is gone (a hangup), or the tee the output went
# through died with a Ctrl+C. Printing is best effort and never stops the
# script. bash keeps the text of a failed write in its buffer and writes it
# into whatever it writes next - a command substitution among them, which
# then reads the script's own messages back instead of a pid - so the buffer
# is flushed to /dev/null at once.
output_lost() {
	exec >/dev/null 2>&1
	printf ''
	return 0
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
#
# Starting again a job or service this run stopped is pushed on the record's
# own last list, run after the rest of the record: only once every file the
# program reads - its binary, its settings - is back. In the record itself it
# would run before the files changed earlier in the run are restored, and the
# old job would start this run's binary.
#
# The record is also kept on disk, in JOURNAL_DIR, written whole before each
# step, with the copies of the files the run replaced. A run that ends with no
# chance to take back - killed, or the machine losing power - leaves it there,
# and the next run takes it back before it does anything else. It holds
# commands, paths and package names, never the password, and only this
# account may read or write it: what it holds is run.

UNDO_MAIN=()
UNDO_TOR=()
UNDO_MAIN_LAST=()
UNDO_TOR_LAST=()
UNDO_INTO=MAIN
# COMMITTED is set once the server answers on its service page: from there on
# the installation stands, and what fails after it is reported, not undone.
COMMITTED=0
# UNDO_FAILED is set when a step could not be taken back.
UNDO_FAILED=0
# SERVER_LOCKED_AGAIN is set when taking back started the server that ran
# before the run: it starts locked, as every start does.
SERVER_LOCKED_AGAIN=0
# The service page's port of the server that ran before the run, for what
# to say when taking back started it again.
PREV_STATUS_PORT=$NOX_DEFAULT_STATUS_PORT
# NOX_EXITING is set once the run is on its way out: a signal then only
# stops further signals, and the taking back goes on.
NOX_EXITING=""
nox_status=0
# JOURNAL_OPEN is set once the record has its folder on disk.
JOURNAL_OPEN=0
# UNDO_FAILED_STEPS keeps the steps that could not be taken back: they stay
# in the record on disk, for the owner.
UNDO_FAILED_STEPS=()

# journal_open makes the folder of the record on disk, this account's alone,
# the first time the run records a step.
journal_open() {
	[ "$JOURNAL_OPEN" = 0 ] || return 0
	case $JOURNAL_DIR in
	/*/nox-install) ;;
	*) die "no folder for the record of changes: $JOURNAL_DIR" ;;
	esac
	mkdir -p "$JOURNAL_DIR" || die "cannot create $JOURNAL_DIR"
	chmod 700 "$JOURNAL_DIR" || die "cannot set the mode of $JOURNAL_DIR"
	JOURNAL_OPEN=1
}

# journal_write writes the record as it stands to disk - whole, through a
# rename, so the file is always one complete record. Its first line names the
# run's process: a run that finds the record knows whether the one that wrote
# it still goes.
journal_write() {
	local name n i entry
	journal_open
	{
		printf 'nox-install-journal 1 %s\n' "$$"
		for name in TOR MAIN TOR_LAST MAIN_LAST FAILED_STEPS; do
			eval "n=\${#UNDO_${name}[@]}"
			i=0
			while [ "$i" -lt "$n" ]; do
				eval "entry=\${UNDO_${name}[$i]}"
				printf '%s\t%s\n' "${name%_STEPS}" "$entry"
				i=$((i + 1))
			done
		done
	} >"$JOURNAL_DIR/journal.new" && mv -f "$JOURNAL_DIR/journal.new" "$JOURNAL_DIR/journal"
}

# journal_close removes the record and the copies from disk: the run is
# taken back, or it stands.
journal_close() {
	local p
	case $JOURNAL_DIR in
	/*/nox-install) rm -rf "$JOURNAL_DIR" ;;
	esac
	JOURNAL_OPEN=0
	# A check leaves its prefix as it found it: the folders made for the
	# record go too, as far as they are empty. The system's own are always
	# there.
	if [ -n "$OPT_PREFIX" ]; then
		p=$(dirname "$JOURNAL_DIR")
		while [ "$p" != "$OPT_PREFIX" ] && [ "$p" != / ] && rmdir "$p" 2>/dev/null; do
			p=$(dirname "$p")
		done
	fi
}

# journal_keep_failed sets a record aside whose taking back did not finish,
# with the copies of the replaced files beside it, for the owner to look at.
journal_keep_failed() {
	if [ -f "$JOURNAL_DIR/journal" ]; then
		mv -f "$JOURNAL_DIR/journal" "$JOURNAL_DIR/journal.failed"
	fi
	warn "what was not taken back is listed in $JOURNAL_DIR/journal.failed, the copies of the files the run replaced beside it; put it right, remove $JOURNAL_DIR, and run the script again"
}

# commit_run marks the installation as standing: the record on disk goes
# first, so a run that ends after this point is never taken back by the next
# one, then the copies with it.
commit_run() {
	rm -f "$JOURNAL_DIR/journal"
	COMMITTED=1
	journal_close
}

# journal_trusted says whether the record on disk can only have been written
# by this account: its folder and its file are this account's, and nobody
# else may write to them.
journal_trusted() {
	local n
	n=$(find "$JOURNAL_DIR" "$JOURNAL_DIR/journal" -prune -user "$(id -u)" ! -perm -0020 ! -perm -0002 2>/dev/null | wc -l | tr -d ' ')
	[ "$n" = 2 ]
}

# journal_owner_alive PID says whether the run that wrote the record still
# goes: that process lives and is this script.
journal_owner_alive() {
	local args
	[ -n "$1" ] && [ "$1" != "$$" ] || return 1
	args=$(ps -p "$1" -o args= 2>/dev/null) || return 1
	case $args in
	*install-linux.sh* | *install-macos.sh*) return 0 ;;
	esac
	return 1
}

# resume_interrupted takes back what a run before this one changed and left
# recorded on disk - it ended with no chance to take it back: killed, or the
# machine went down - before this run looks at the machine. Nothing cuts it
# short. When all of it is back this run goes on; when not, it stops, with
# the record set aside.
resume_interrupted() {
	local header pid line name entry first=1
	if [ -e "$JOURNAL_DIR/journal.failed" ]; then
		die "a run before this one could not take back everything it changed: what is left is listed in $JOURNAL_DIR/journal.failed, the copies of the files it replaced beside it; put it right, remove $JOURNAL_DIR, and run the script again"
	fi
	[ -f "$JOURNAL_DIR/journal" ] || return 0
	journal_trusted || die "$JOURNAL_DIR holds a record of changes that others could have written; look at it, remove it, and run the script again"
	IFS= read -r header <"$JOURNAL_DIR/journal" || header=""
	case $header in
	"nox-install-journal 1 "*) pid=${header##* } ;;
	*) die "$JOURNAL_DIR/journal is not a record this script wrote; look at it, remove $JOURNAL_DIR, and run the script again" ;;
	esac
	if journal_owner_alive "$pid"; then
		die "another run of this script is under way (process $pid): let it finish, and run the script again"
	fi
	trap '' INT TERM HUP QUIT PIPE
	step "Taking back an interrupted run"
	say "A run before this one ended before it finished - it was killed, or the machine went down - and"
	say "what it changed is still in place. That is taken back first."
	UNDO_TOR=() UNDO_MAIN=() UNDO_TOR_LAST=() UNDO_MAIN_LAST=()
	while IFS= read -r line; do
		if [ "$first" = 1 ]; then
			first=0
			continue
		fi
		name=${line%%$'\t'*}
		entry=${line#*$'\t'}
		case $name in
		TOR | MAIN | TOR_LAST | MAIN_LAST) eval "UNDO_${name}[\${#UNDO_${name}[@]}]=\$entry" ;;
		# A step that failed before is reported, not tried again unseen.
		FAILED)
			UNDO_FAILED_STEPS[${#UNDO_FAILED_STEPS[@]}]=$entry
			UNDO_FAILED=1
			;;
		esac
	done <"$JOURNAL_DIR/journal"
	JOURNAL_OPEN=1
	undo_run TOR
	undo_run MAIN
	if [ "$UNDO_FAILED" != 0 ]; then
		journal_keep_failed
		# The server that ran before may be running again all the same, and
		# locked: how it opens is said here too, from its own service.
		detect_install
		say_server_locked_again
		die "not everything the interrupted run changed could be taken back: see the lines above"
	fi
	journal_close
	say "What the interrupted run changed is taken back."
	trap - INT TERM HUP QUIT PIPE
}

undo_push() {
	if [ "$UNDO_INTO" = TOR ]; then
		UNDO_TOR[${#UNDO_TOR[@]}]=$1
	else
		UNDO_MAIN[${#UNDO_MAIN[@]}]=$1
	fi
	journal_write || die "cannot write the record of changes in $JOURNAL_DIR"
}

# undo_push_last pushes a start of what this run stopped: run once the rest of
# the record is taken back.
undo_push_last() {
	if [ "$UNDO_INTO" = TOR ]; then
		UNDO_TOR_LAST[${#UNDO_TOR_LAST[@]}]=$1
	else
		UNDO_MAIN_LAST[${#UNDO_MAIN_LAST[@]}]=$1
	fi
	journal_write || die "cannot write the record of changes in $JOURNAL_DIR"
}

# undo_run MAIN|TOR runs that record newest first, then its last list newest
# first, and empties both.
undo_run() {
	undo_steps "UNDO_$1"
	undo_steps "UNDO_$1_LAST"
}

# undo_steps NAME runs one list of steps newest first. Each step leaves the
# list - and the record on disk - once it ran, so taking back that is
# interrupted goes on from that step, not from the start.
undo_steps() {
	local name=$1 count i cmd
	eval "count=\${#${name}[@]}"
	i=$((count - 1))
	while [ "$i" -ge 0 ]; do
		eval "cmd=\${${name}[$i]}"
		if ! eval "$cmd"; then
			warn "could not undo: $cmd"
			UNDO_FAILED=1
			UNDO_FAILED_STEPS[${#UNDO_FAILED_STEPS[@]}]=$cmd
		fi
		eval "unset '${name}[$i]'"
		journal_write 2>/dev/null || true
		i=$((i - 1))
	done
}

# undo_pending says whether anything is recorded to take back.
undo_pending() {
	[ ${#UNDO_TOR[@]} -gt 0 ] || [ ${#UNDO_MAIN[@]} -gt 0 ] || [ ${#UNDO_TOR_LAST[@]} -gt 0 ] || [ ${#UNDO_MAIN_LAST[@]} -gt 0 ]
}

# undo_keep_tor moves the tor record into the main one, and its last list into
# the main last list: tor is in place, and from here on only a failure of the
# whole run takes it back.
undo_keep_tor() {
	local i=0
	while [ "$i" -lt ${#UNDO_TOR[@]} ]; do
		UNDO_MAIN[${#UNDO_MAIN[@]}]=${UNDO_TOR[$i]}
		i=$((i + 1))
	done
	i=0
	while [ "$i" -lt ${#UNDO_TOR_LAST[@]} ]; do
		UNDO_MAIN_LAST[${#UNDO_MAIN_LAST[@]}]=${UNDO_TOR_LAST[$i]}
		i=$((i + 1))
	done
	UNDO_TOR=()
	UNDO_TOR_LAST=()
	UNDO_INTO=MAIN
	journal_write || die "cannot write the record of changes in $JOURNAL_DIR"
}

WORK=""

on_exit() {
	local status=$1
	# Nothing may cut the taking back short - a second Ctrl+C, a hangup, a
	# closed pipe, a write that fails: half of it would leave the machine in a
	# state nobody chose. So the signals are ignored from here on, by the
	# commands it runs too, and a failed command no longer ends the script:
	# when the terminal is gone, or the tee it wrote through died with the
	# Ctrl+C, what it prints is lost, and that is all.
	trap '' INT TERM HUP QUIT PIPE
	set +e
	if [ -t 0 ]; then
		stty echo 2>/dev/null
	fi
	if [ "$status" -ne 0 ] && [ "$COMMITTED" = 0 ] && undo_pending; then
		printf '\n' >&2 || output_lost
		warn "the installation did not finish; taking back what this run changed"
		undo_run TOR
		undo_run MAIN
		if [ "$UNDO_FAILED" != 0 ]; then
			warn "not everything could be taken back: see the lines above"
			journal_keep_failed
		elif [ "$SERVER_LOCKED_AGAIN" = 1 ]; then
			say "Everything this run changed was taken back."
		else
			say "This machine is as it was before the run."
		fi
		say_server_locked_again
	fi
	if [ "$COMMITTED" = 0 ] && [ "$UNDO_FAILED" = 0 ] && [ "$JOURNAL_OPEN" = 1 ]; then
		journal_close
	fi
	if [ -n "$WORK" ] && [ -d "$WORK" ]; then
		rm -rf "$WORK"
	fi
	exit "$status"
}

# say_server_locked_again is what to say when taking back started the server
# that ran before: it starts locked, as every start does, and how it opens.
say_server_locked_again() {
	[ "$SERVER_LOCKED_AGAIN" = 1 ] || return 0
	say "The server that ran before was started again and, as after every start, it is locked until its"
	say "password is entered - on the service page, http://127.0.0.1:$PREV_STATUS_PORT on this machine, or with:"
	say "    $NOXD_CMD unlock$(status_flag_for "$PREV_STATUS_PORT")"
}

# arm_traps makes every way a run can be stopped one that takes it back. A
# signal with no trap of its own would end the script with the EXIT trap
# seeing the last command's status - 0 - as if the run had finished: a closed
# terminal or a dropped SSH connection (HUP), Ctrl+\ (QUIT), and the tee the
# output goes through dying (PIPE).
#
# Each trap ignores every one of these signals before it exits: a closing
# terminal sends its hangup twice, a fraction of a millisecond apart, and a
# second exit run inside the EXIT trap ended the script before it took
# anything back. For the same reason the EXIT trap marks the way out before
# it does anything else - a signal arriving after an error then only stops
# further signals - and takes the status first, as the mark resets it.
arm_traps() {
	trap 'nox_status=$?; NOX_EXITING=1; on_exit "$nox_status"' EXIT
	trap 'trap "" INT TERM HUP QUIT PIPE; [ -n "$NOX_EXITING" ] || exit 130' INT
	trap 'trap "" INT TERM HUP QUIT PIPE; [ -n "$NOX_EXITING" ] || exit 143' TERM
	trap 'trap "" INT TERM HUP QUIT PIPE; [ -n "$NOX_EXITING" ] || exit 129' HUP
	trap 'trap "" INT TERM HUP QUIT PIPE; [ -n "$NOX_EXITING" ] || exit 131' QUIT
	trap 'trap "" INT TERM HUP QUIT PIPE; [ -n "$NOX_EXITING" ] || exit 141' PIPE
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
	# A link stops the walk, and one that leads nowhere is refused before
	# anything is recorded: the folder of a second disk that is not mounted
	# looks missing, and taking back a mkdir that failed through it would
	# delete the owner's link.
	while [ ! -e "$p" ] && [ ! -L "$p" ]; do
		top=$p
		p=$(dirname "$p")
	done
	if [ -L "$p" ] && [ ! -e "$p" ]; then
		die "$p is a link to $(readlink "$p"), which is not there: mount or fix it, and run the script again"
	fi
	if [ -z "$top" ]; then
		[ -d "$path" ] || die "$path is not a directory"
		return 0
	fi
	# Recorded before the step, as every change is: an interrupt that lands
	# between a change and its record would leave the change behind, and
	# removing what was never made is nothing.
	undo_push "rm -rf $(q "$top")"
	mkdir -p "$path" || die "cannot create $path"
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
# the previous file is kept beside the record on disk until the run ends.
put_file() {
	local src=$1 dest=$2 mode=$3 owner=${4:-} group=${5:-} keep
	if [ -e "$dest" ]; then
		# Beside the record on disk: a run taken back by the next one finds
		# the copy there.
		journal_open
		keep=$(mktemp "$JOURNAL_DIR/previous.XXXXXX") || die "cannot keep a copy of $dest"
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

# refuse_low_port PORT LOWEST OPTION refuses a port below LOWEST, where the
# server's own account may not listen on this system. Such a server would
# answer on its service page and fail only when the password opens its data
# and the main port is bound - or, for the page's port, never start at all.
refuse_low_port() {
	local port=$1 lowest=$2 option=$3
	[ "$port" -lt "$lowest" ] || return 0
	if [ "$option" = --port ]; then
		die "port $port is below $lowest, and the server's own account may not listen there on this system: use $lowest or above with --port (the default is $NOX_DEFAULT_PORT); to reach the server from the internet on $port, forward that port on your router to it"
	fi
	die "port $port, for the service page, is below $lowest, and the server's own account may not listen there on this system: use $lowest or above with --status-port (the default is $NOX_DEFAULT_STATUS_PORT)"
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

# take_given_binary sets NEW_BINARY to the noxd given with --binary - on a
# Mac, to a copy of it in the scratch directory without the quarantine that
# AirDrop, Messages, Mail and browsers put on every file they bring:
# Gatekeeper refuses to run a quarantined program nobody notarised, which
# every noxd is, and the check below runs it. The copy is what is checked and
# what is installed; the file given is left as it was.
take_given_binary() {
	NEW_BINARY=$OPT_BINARY
	[ "$(uname -s)" = Darwin ] || return 0
	mkdir -p "$WORK/given"
	NEW_BINARY=$WORK/given/noxd
	cp "$OPT_BINARY" "$NEW_BINARY" || die "cannot copy $OPT_BINARY"
	chmod 755 "$NEW_BINARY" || die "cannot make the copy of $OPT_BINARY runnable"
	xattr -d com.apple.quarantine "$NEW_BINARY" 2>/dev/null || true
	if xattr -p com.apple.quarantine "$NEW_BINARY" >/dev/null 2>&1; then
		die "macOS keeps the copy of $OPT_BINARY in quarantine, and will not run it: lift it with xattr -d com.apple.quarantine $OPT_BINARY and run the script again"
	fi
}

# prepare_binary sets NEW_BINARY: the noxd given with --binary, or one built
# here from the repository beside this script. Nothing is installed yet.
prepare_binary() {
	local go out src
	if [ -n "$OPT_BINARY" ]; then
		take_given_binary
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
	local help what=${OPT_BINARY:-$NEW_BINARY} why=""
	help=$("$NEW_BINARY" unlock -h 2>&1 || true)
	case $help in
	*-status-addr*) ;;
	*)
		if [ -n "$help" ]; then
			why=" (it said: $(printf '%s\n' "$help" | head -n 1))"
		fi
		if [ -n "$OPT_BINARY" ] && [ "$(uname -s)" = Darwin ]; then
			# Named, because it is the usual reason a Mac will not run a
			# program carried over from another one - and it is ruled out.
			why="$why; a quarantine is not the cause - the copy that was tried had none"
		fi
		die "$what does not run here as a NOX server with 'noxd unlock'$why; build it for this system"
		;;
	esac
	help=$("$NEW_BINARY" link -h 2>&1 || true)
	case $help in
	*-qr*) ;;
	*) die "$what has no 'noxd link -qr'; build it from this repository" ;;
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
	status_flag_for "$STATUS_PORT"
}

# status_flag_for PORT is status_flag for the service page on PORT.
status_flag_for() {
	if [ "$1" != "$NOX_DEFAULT_STATUS_PORT" ]; then
		printf ' -status-addr 127.0.0.1:%s' "$1"
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

# say_backups says where a backup can go. `noxd backup` has the running
# server write the file, as its own account, which can write in its own
# folder only - so the installation has a folder for backups there.
say_backups() {
	local noxd_cmd=$1 file
	file="$BACKUP_DIR/nox-$(date +%Y-%m-%d).tar"
	say ""
	say "A backup is written by the running server, as its own account, which can write only in its own"
	say "folder - $BACKUP_DIR is there for backups:"
	say "    $noxd_cmd backup$(status_flag) \"$file\""
	if [ -n "$OPT_PREFIX" ]; then
		say "Then copy it off this machine:"
		say "    cp \"$file\" ~/"
	else
		say "Then copy it off this machine; there, only administrators can read it:"
		say "    sudo cp \"$file\" ~/ && sudo chown \"\$USER\" ~/$(basename "$file")"
	fi
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
