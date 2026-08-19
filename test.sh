#!/bin/sh
# test.sh builds a throwaway git repository with a known history, then it
# asserts what git-why prints. The test touches no other repository, and it
# reads no configuration from this machine. Run it with ./test.sh.

set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
GIT_WHY=$HERE/git-why
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Cut the fixture off from this machine, so the result is the same everywhere.
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_SYSTEM=/dev/null
GIT_AUTHOR_NAME='Test Author'
GIT_AUTHOR_EMAIL='author@example.com'
GIT_COMMITTER_NAME='Test Author'
GIT_COMMITTER_EMAIL='author@example.com'
GIT_AUTHOR_DATE='2020-01-01T00:00:00Z'
GIT_COMMITTER_DATE='2020-01-01T00:00:00Z'
export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
export GIT_AUTHOR_DATE GIT_COMMITTER_DATE

FAILURES=0
CHECKS=0

check() { # name, wanted substring, actual text
	CHECKS=$((CHECKS + 1))
	if printf '%s\n' "$3" | grep -qF -- "$2"; then
		printf 'ok    %s\n' "$1"
	else
		printf 'FAIL  %s\n  wanted: %s\n  got:\n%s\n\n' "$1" "$2" "$3"
		FAILURES=$((FAILURES + 1))
	fi
}

check_absent() { # name, unwanted substring, actual text
	CHECKS=$((CHECKS + 1))
	if printf '%s\n' "$3" | grep -qF -- "$2"; then
		printf 'FAIL  %s\n  did not want: %s\n  got:\n%s\n\n' "$1" "$2" "$3"
		FAILURES=$((FAILURES + 1))
	else
		printf 'ok    %s\n' "$1"
	fi
}

check_equal() { # name, wanted value, actual value
	CHECKS=$((CHECKS + 1))
	if [ "$2" = "$3" ]; then
		printf 'ok    %s\n' "$1"
	else
		printf 'FAIL  %s\n  wanted: %s\n  got: %s\n\n' "$1" "$2" "$3"
		FAILURES=$((FAILURES + 1))
	fi
}

# ---------------------------------------------------------------------------
# Build the fixture history. Every assertion below reads this history.
# ---------------------------------------------------------------------------
cd "$WORK"
git init -q -b main .
: >"$WORK/no-ignored-revs"

commit() { # subject, body
	git add -A
	git commit -q -m "$1" -m "$2"
}

# 1. The cap. This commit holds the reason that the later tests look for.
cat >limits.py <<'EOF'
LIMIT = 100


def fetch(items):
    return items[:LIMIT]
EOF
cat >notes.md <<'EOF'
# Notes

The fetch cap exists because the vendor bills for each item and a full sync would cost more than the daily budget allows.
EOF
commit 'Cap the vendor fetch at 100 items' \
	'The vendor bills for each item. A cap of 100 holds one run inside the
daily budget. The number comes from the contract, not from a benchmark.'
C_CAP=$(git rev-parse --short=8 HEAD)

# 2. The flush helper. A later commit moves this block to another file.
cat >>limits.py <<'EOF'


def flush(items, sink):
    dropped = items[LIMIT:]
    if not dropped:
        return 0
    for item in dropped:
        sink.append(item)
    return len(dropped)
EOF
commit 'Return the items that the cap dropped' \
	'The cap dropped items and told nobody. flush hands them to a sink, so the
caller can queue a second run instead of losing the data.'
C_FLUSH=$(git rev-parse --short=8 HEAD)

# 3. A prose reflow. It splits one sentence across two lines. It changes no
# meaning. "git blame -w" cannot see through it, because the words moved.
cat >notes.md <<'EOF'
# Notes

The fetch cap exists because the vendor bills for each item. A full sync
would cost more than the daily budget allows.
EOF
commit 'Split the longest sentence in the notes' \
	'House style caps a sentence at 25 words. This commit changes no meaning.'
C_REFLOW=$(git rev-parse HEAD)
C_REFLOW_SHORT=$(git rev-parse --short=8 HEAD)

# 4. Hide the reflow commit, the way this repository and GitHub both read it.
cat >.git-blame-ignore-revs <<EOF
# Reflow only. It changed no meaning.
$C_REFLOW
EOF
commit 'Hide the reflow commit from blame' 'A reflow is not a reason.'

# 5. Move the flush block into its own file. Nothing inside the block changes.
sed -n '1,5p' limits.py >limits.tmp && mv limits.tmp limits.py
cat >queue.py <<'EOF'
from limits import LIMIT


def flush(items, sink):
    dropped = items[LIMIT:]
    if not dropped:
        return 0
    for item in dropped:
        sink.append(item)
    return len(dropped)
EOF
commit 'Move the flush helper into its own file' \
	'limits.py held two jobs. The queue owns the retry path now.'
C_MOVE=$(git rev-parse --short=8 HEAD)

# 6. Add a constant, so limits.py spans two commits at HEAD.
cat >>limits.py <<'EOF'

RETRIES = 3
EOF
commit 'Retry a failed fetch three times' \
	'The vendor drops about one call in fifty. Three tries clear that rate
without hiding a real outage.'
C_RETRIES=$(git rev-parse --short=8 HEAD)

# 7. One commit that owns two separate blocks of the same file. A later
# commit splits its lines apart. This is the case that "uniq -c" gets wrong.
cat >split.py <<'EOF'
alpha line one
alpha line two
alpha line three
alpha line four
EOF
commit 'Add the alpha block' 'The alpha block starts as four lines together.'
C_ALPHA=$(git rev-parse --short=8 HEAD)
cat >split.py <<'EOF'
alpha line one
alpha line two
beta line one
beta line two
alpha line three
alpha line four
EOF
commit 'Push the beta block into the middle of alpha' \
	'The beta lines belong between the halves of alpha.'

# ---------------------------------------------------------------------------
# Assertions.
# ---------------------------------------------------------------------------
printf '\n--- one line, one commit ---\n'
OUT=$("$GIT_WHY" limits.py 5)
check 'names the commit that set the cap' "$C_CAP" "$OUT"
check 'prints the subject' 'Cap the vendor fetch at 100 items' "$OUT"
check 'prints the body, which holds the reason' \
	'The number comes from the contract' "$OUT"
check 'counts one line and one commit' '1 line, 1 commit' "$OUT"
check_absent 'prints no author' 'Test Author' "$OUT"
check_absent 'prints no date' '2020-01-01' "$OUT"
check_absent 'prints no source line' 'return items[:LIMIT]' "$OUT"

printf '\n--- a range across two commits ---\n'
OUT=$("$GIT_WHY" limits.py 1-7)
check 'counts seven lines and two commits' '7 lines, 2 commits' "$OUT"
check 'names the cap commit' "$C_CAP" "$OUT"
check 'names the retry commit' "$C_RETRIES" "$OUT"
check 'ranks the cap commit first, with five lines' "$C_CAP  5 lines" "$OUT"
check 'gives the retry commit two lines' "$C_RETRIES  2 lines" "$OUT"
check 'prints both reasons' 'Three tries clear that rate' "$OUT"

printf '\n--- one commit in two separate blocks counts once ---\n'
# The alpha commit owns lines 1-2 and lines 5-6. The beta commit sits between
# them. "uniq -c" only joins neighbour lines, so it would print alpha twice.
OUT=$("$GIT_WHY" split.py 1-6)
check 'counts six lines and two commits' '6 lines, 2 commits' "$OUT"
COUNT=$(printf '%s\n' "$OUT" | grep -c "^$C_ALPHA " || true)
check_equal 'lists the split commit exactly once' 1 "$COUNT"
check 'adds up both of its blocks' "$C_ALPHA  4 lines" "$OUT"

printf '\n--- a reflow commit hides the reason ---\n'
OUT=$("$GIT_WHY" --ignore-revs-file "$WORK/no-ignored-revs" notes.md 3)
check 'without ignore-revs, the reflow commit is the answer' \
	"$C_REFLOW_SHORT" "$OUT"
check 'and it says nothing about the reason' \
	'Split the longest sentence in the notes' "$OUT"

printf '\n--- git-why sees through the reflow commit ---\n'
OUT=$("$GIT_WHY" notes.md 3)
check 'reaches the real reason' "$C_CAP" "$OUT"
check 'prints the real reason' 'The vendor bills for each item' "$OUT"
check_absent 'hides the reflow commit' "$C_REFLOW_SHORT" "$OUT"

printf '\n--- a moved block keeps its original reason ---\n'
OUT=$("$GIT_WHY" queue.py 4-10)
check 'follows the move back to the flush commit' "$C_FLUSH" "$OUT"
check 'prints the reason for the moved code' 'queue a second run' "$OUT"
check_absent 'the move commit is not the answer' "$C_MOVE" "$OUT"

printf '\n--- the output says when it cuts a body ---\n'
OUT=$("$GIT_WHY" -b 1 limits.py 5)
check 'says that it cut the body' 'body cut at 1 lines' "$OUT"
check 'points at the full command' "git log -1 $C_CAP" "$OUT"

printf '\n--- the output says when it drops a commit ---\n'
OUT=$("$GIT_WHY" -n 1 limits.py 1-7)
check 'names the commits it did not open' 'Also in this range: 1 commit' "$OUT"
check 'still gives the dropped subject' 'Retry a failed fetch three times' "$OUT"
check 'points at the full command' 'Read any body with: git log -1 <sha>' "$OUT"

printf '\n--- whole file mode ---\n'
OUT=$("$GIT_WHY" limits.py)
check 'ranks the commits' "$C_CAP" "$OUT"
check_absent 'prints no body' 'The number comes from the contract' "$OUT"
check_absent 'prints no blame table' 'def fetch' "$OUT"

printf '\n--- errors ---\n'
set +e
OUT=$("$GIT_WHY" limits.py 1-9999 2>&1)
check_equal 'a range past the end exits 2' 2 $?
check 'and says what is wrong' 'past the end' "$OUT"
OUT=$("$GIT_WHY" untracked.py 1 2>&1)
check_equal 'an untracked file exits 2' 2 $?
check 'and says what is wrong' 'does not track' "$OUT"
OUT=$(cd / && "$GIT_WHY" limits.py 1 2>&1)
check_equal 'a directory outside a repository exits 2' 2 $?
check 'and says what is wrong' 'not a git repository' "$OUT"
OUT=$("$GIT_WHY" --ignore-revs-file "$WORK/absent" notes.md 3 2>&1)
check_equal 'a missing ignore-revs file exits 2' 2 $?
OUT=$("$GIT_WHY" limits.py 9-2 2>&1)
check_equal 'a backwards range exits 1' 1 $?
OUT=$("$GIT_WHY" limits.py bad-range 2>&1)
check_equal 'a range that is not a number exits 1' 1 $?
OUT=$("$GIT_WHY" limits.py 1 2 3 2>&1)
check_equal 'too many arguments exits 1' 1 $?
OUT=$("$GIT_WHY" --nope limits.py 1 2>&1)
check_equal 'an unknown option exits 1' 1 $?
OUT=$("$GIT_WHY" 2>&1)
check_equal 'no arguments exits 1' 1 $?
OUT=$("$GIT_WHY" --help 2>&1)
check_equal '--help exits 0' 0 $?
check 'and shows a real example' 'git-why internal/cli/cli.go 240-270' "$OUT"
set -e

printf '\n%s checks, %s failures\n' "$CHECKS" "$FAILURES"
[ "$FAILURES" -eq 0 ] || exit 1
