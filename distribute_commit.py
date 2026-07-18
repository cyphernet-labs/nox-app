#!/usr/bin/env python3
"""
Safely redistribute commit dates across a selected commit range.

Features
- Validates required parameters
- Validates commit ancestry and date interval
- Refuses to run on dirty working tree
- Shows preview and before/after statistics
- Creates backup branch before rewriting history
- Requires explicit --apply to modify history
- Asks for confirmation unless --yes is supplied

Implementation note
- Rewrites history using `git filter-branch` from start_commit^ to HEAD.
- Only commits between start_commit and end_commit get new timestamps.
- Descendant commits after end_commit are rewritten only because Git requires it,
  but their original dates are preserved.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


DATE_FORMATS = [
    "%Y-%m-%d %H:%M:%S",
    "%Y-%m-%d %H:%M",
    "%Y-%m-%dT%H:%M:%S",
    "%Y-%m-%dT%H:%M",
    "%Y-%m-%d",
    # Dotted variants (e.g. '2026.07.13 08:00:00').
    "%Y.%m.%d %H:%M:%S",
    "%Y.%m.%d %H:%M",
    "%Y.%m.%d",
]

# Formats that carry no time component; matching one means midnight.
DATE_ONLY_FORMATS = {"%Y-%m-%d", "%Y.%m.%d"}


@dataclass(frozen=True)
class CommitInfo:
    sha: str
    short_sha: str
    author_date_iso: str
    subject: str


@dataclass(frozen=True)
class PlannedCommit:
    commit: CommitInfo
    new_date: dt.datetime


class ScriptError(Exception):
    pass


def run_git(args: list[str], cwd: str | None = None, check: bool = True) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and result.returncode != 0:
        raise ScriptError(result.stderr.strip() or result.stdout.strip() or f"git {' '.join(args)} failed")
    return result.stdout.strip()


def ensure_git_repo() -> None:
    try:
        run_git(["rev-parse", "--is-inside-work-tree"])
    except ScriptError as exc:
        raise ScriptError("Current directory is not a Git repository.") from exc


def ensure_clean_worktree() -> None:
    status = run_git(["status", "--porcelain"])
    if status.strip():
        raise ScriptError(
            "Working tree is not clean. Commit, stash, or discard local changes before running this script."
        )


def parse_date(value: str) -> dt.datetime:
    for fmt in DATE_FORMATS:
        try:
            parsed = dt.datetime.strptime(value, fmt)
            if fmt in DATE_ONLY_FORMATS:
                parsed = parsed.replace(hour=0, minute=0, second=0)
            return parsed
        except ValueError:
            continue
    raise ScriptError(
        "Invalid date format: {!r}. Supported formats: YYYY-MM-DD, YYYY-MM-DD HH:MM, YYYY-MM-DD HH:MM:SS, "
        "YYYY-MM-DDTHH:MM, YYYY-MM-DDTHH:MM:SS, and the dotted variants YYYY.MM.DD[ HH:MM[:SS]]. "
        "NOTE: quote any date that contains a space, e.g. --start-date '2026.07.13 08:00:00'.".format(value)
    )


def ensure_commit_exists(commit: str) -> str:
    try:
        return run_git(["rev-parse", "--verify", f"{commit}^{{commit}}"])
    except ScriptError as exc:
        raise ScriptError(f"Commit does not exist or is not resolvable: {commit}") from exc


def is_ancestor(older: str, newer: str) -> bool:
    result = subprocess.run(["git", "merge-base", "--is-ancestor", older, newer])
    return result.returncode == 0


def get_current_branch() -> str:
    branch = run_git(["branch", "--show-current"])
    if not branch:
        raise ScriptError("Detached HEAD is not supported. Check out a branch first.")
    return branch


def get_commit_range(start_commit: str, end_commit: str) -> list[CommitInfo]:
    output = run_git(
        [
            "rev-list",
            "--reverse",
            "--format=%H%x09%h%x09%aI%x09%s",
            f"{start_commit}^..{end_commit}",
        ]
    )
    commits: list[CommitInfo] = []
    for line in output.splitlines():
        if not line or line.startswith("commit "):
            continue
        parts = line.split("\t", 3)
        if len(parts) != 4:
            continue
        sha, short_sha, author_date_iso, subject = parts
        commits.append(CommitInfo(sha=sha, short_sha=short_sha, author_date_iso=author_date_iso, subject=subject))
    if not commits:
        raise ScriptError("No commits found in the selected range.")
    return commits


def compute_even_dates(start_date: dt.datetime, end_date: dt.datetime, count: int) -> list[dt.datetime]:
    if count <= 0:
        raise ScriptError("Commit count must be positive.")
    if count == 1:
        return [start_date]

    total_seconds = (end_date - start_date).total_seconds()
    if total_seconds < 0:
        raise ScriptError("End date must be later than start date.")

    step = total_seconds / (count - 1)
    return [start_date + dt.timedelta(seconds=step * i) for i in range(count)]


def format_git_date(value: dt.datetime) -> str:
    return value.strftime("%Y-%m-%d %H:%M:%S")


def bucket_by_day(dates: Iterable[dt.datetime]) -> Counter[str]:
    return Counter(d.strftime("%Y-%m-%d") for d in dates)


def parse_iso_to_dt(value: str) -> dt.datetime:
    normalized = value.replace("Z", "+00:00")
    return dt.datetime.fromisoformat(normalized)


def print_summary(commits: list[CommitInfo], planned_dates: list[dt.datetime], start_date: dt.datetime, end_date: dt.datetime) -> None:
    old_dates = [parse_iso_to_dt(c.author_date_iso) for c in commits]
    old_buckets = bucket_by_day(old_dates)
    new_buckets = bucket_by_day(planned_dates)

    print("\n=== Range summary ===")
    print(f"Selected commits : {len(commits)}")
    print(f"First commit     : {commits[0].short_sha}  {commits[0].subject}")
    print(f"Last commit      : {commits[-1].short_sha}  {commits[-1].subject}")
    print(f"Date window      : {format_git_date(start_date)}  ->  {format_git_date(end_date)}")

    if len(planned_dates) > 1:
        interval_seconds = (planned_dates[1] - planned_dates[0]).total_seconds()
        print(f"Even step        : {interval_seconds:.2f} seconds")
    else:
        print("Even step        : single commit (end_date is ignored)")

    print("\n=== Distribution by day: BEFORE ===")
    for day, count in sorted(old_buckets.items()):
        print(f"{day}: {count}")

    print("\n=== Distribution by day: AFTER ===")
    for day, count in sorted(new_buckets.items()):
        print(f"{day}: {count}")

    print("\n=== Planned rewrite preview ===")
    for idx, (commit, new_date) in enumerate(zip(commits, planned_dates), start=1):
        old_str = format_git_date(parse_iso_to_dt(commit.author_date_iso))
        new_str = format_git_date(new_date)
        print(f"{idx:>4}. {commit.short_sha}  {old_str}  ->  {new_str}  | {commit.subject}")


def create_backup_branch() -> str:
    timestamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_branch = f"backup/rewrite-dates-{timestamp}"
    run_git(["branch", backup_branch, "HEAD"])
    return backup_branch


def ensure_tool_available(tool: str) -> None:
    if shutil.which(tool) is None:
        raise ScriptError(f"Required tool is not available: {tool}")


def write_env_filter_file(planned: list[PlannedCommit], destination: Path) -> None:
    lines = ["case \"$GIT_COMMIT\" in"]
    for item in planned:
        value = format_git_date(item.new_date)
        lines.append(f"  {item.commit.sha})")
        lines.append(f"    export GIT_AUTHOR_DATE='{value}'")
        lines.append(f"    export GIT_COMMITTER_DATE='{value}'")
        lines.append("    ;;")
    lines.append("esac")
    destination.write_text("\n".join(lines) + "\n", encoding="utf-8")


def apply_rewrite(start_commit: str, planned: list[PlannedCommit], yes: bool) -> None:
    ensure_tool_available("git")

    backup_branch = create_backup_branch()
    print("\n=== Safety ===")
    print(f"Backup branch created: {backup_branch}")
    print("If you want to undo the rewrite, run:")
    print(f"  git reset --hard {backup_branch}")

    if not yes:
        reply = input("\nProceed with history rewrite? Type 'yes' to continue: ").strip().lower()
        if reply != "yes":
            print("Aborted by user. No changes were made.")
            return

    with tempfile.TemporaryDirectory(prefix="rewrite-dates-") as tmp_dir:
        env_filter_path = Path(tmp_dir) / "env-filter.sh"
        write_env_filter_file(planned, env_filter_path)
        env_filter_script = env_filter_path.read_text(encoding="utf-8")

        print("\nRewriting history...")
        env = os.environ.copy()
        env["FILTER_BRANCH_SQUELCH_WARNING"] = "1"

        result = subprocess.run(
            [
                "git",
                "filter-branch",
                "-f",
                "--env-filter",
                env_filter_script,
                f"{start_commit}^..HEAD",
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=env,
        )
        print(result.stdout)
        if result.returncode != 0:
            raise ScriptError(
                "History rewrite failed. Your backup branch still points to the previous state: "
                f"{backup_branch}"
            )

    print("Rewrite completed successfully.")
    print("Review the result with:")
    print("  git log --graph --decorate --oneline --date=iso")
    print("If this branch was already pushed, use:")
    print("  git push --force-with-lease")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Evenly redistribute commit dates between start_date and end_date for commits from start_commit to end_commit."
    )
    parser.add_argument("--start-date", required=True, help="Start date. Example: '2024-01-01 09:00'")
    parser.add_argument("--end-date", required=True, help="End date. Example: '2024-01-10 18:00'")
    parser.add_argument("--start-commit", required=True, help="Older commit in the selected range")
    parser.add_argument("--end-commit", required=True, help="Newer commit in the selected range")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually rewrite history. Without this flag the script only shows a preview.",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Skip interactive confirmation. Only valid together with --apply.",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.yes and not args.apply:
        raise ScriptError("--yes can only be used together with --apply.")

    ensure_git_repo()
    ensure_clean_worktree()

    start_date = parse_date(args.start_date)
    end_date = parse_date(args.end_date)
    if end_date < start_date:
        raise ScriptError("End date cannot be earlier than start date.")

    start_commit = ensure_commit_exists(args.start_commit)
    end_commit = ensure_commit_exists(args.end_commit)

    if not is_ancestor(start_commit, end_commit):
        raise ScriptError("start_commit must be an ancestor of end_commit.")

    current_branch = get_current_branch()
    head_commit = ensure_commit_exists("HEAD")
    if not is_ancestor(end_commit, head_commit):
        raise ScriptError(
            f"end_commit is not reachable from HEAD of the current branch ({current_branch}). "
            "Check out the correct branch first."
        )

    commits = get_commit_range(start_commit, end_commit)
    new_dates = compute_even_dates(start_date, end_date, len(commits))
    planned = [PlannedCommit(commit=c, new_date=d) for c, d in zip(commits, new_dates)]

    print(f"Current branch: {current_branch}")
    print_summary(commits, new_dates, start_date, end_date)

    if not args.apply:
        print("\nPreview only. No changes were made.")
        print("Run the same command with --apply to rewrite history.")
        return 0

    apply_rewrite(start_commit=start_commit, planned=planned, yes=args.yes)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ScriptError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        raise SystemExit(130)
