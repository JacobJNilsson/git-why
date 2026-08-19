# git-why

`git-why` answers one question about a line range: why is this line the way
it is. It prints the commits that explain the lines, and it prints their
message bodies. It prints no blame table.

```
$ git-why -n 2 -b 4 internal/cli/cli.go 100-140
internal/cli/cli.go:100-140  41 lines, 7 commits

2d5ce162  15 lines  feat: Add worker, ingest, and approval commands
  The state machine becomes operable: one command runs the worker, one
  enqueues a file onto its channel, and one carries the human decision
  that a parked probation run waits for. The approval command is the
  entire rung-zero trust ladder surface on purpose: every probation
  ... body cut at 4 lines.
  Read all of it with: git log -1 2d5ce162

7ee939b0  11 lines  feat(cli): Add a discovery layer - grouped help, a worked example, help <verb> (#240)
  The per-verb -h docs are dense, but the entry point was blank: the bare
  invocation printed one comma-separated verb list with no summaries,
  -h showed only -version, and nothing in the binary narrated the operator
  lifecycle. A new operator (or an LLM driving the CLI) had no map.
  ... body cut at 4 lines.
  Read all of it with: git log -1 7ee939b0

Also in this range: 5 commits
  765149fa  8 lines  feat: Scaffold the orchestrator with the house gate
  93eea9cc  3 lines  refactor(cli): Move the operator-surface rationale into the decision records
  982c7a36  2 lines  feat(tui): add operator console over the CLI's read-and-signal surfaces
  280238ed  1 line  feat(agentenv): Contain the agents that read attacker-controlled files (SB-12)
  5c63a3d8  1 line  feat(cli): State the repo proposal at the gate, and retry it on demand
  Read any body with: git log -1 <sha>
```

The example passes small caps to stay short here. The defaults open 3
commits and print 20 body lines each.

## Why it exists

Git history is a good place to keep the reasons behind the code. It only
works if a reader can get those reasons cheaply. Today `git blame` cannot
give them.

**Blame costs more than the source, and it answers a different question.**
On `internal/importpolicy/importpolicy.go` in the orchestrator repository:

| command | characters |
| --- | ---: |
| the source file itself | 25362 |
| `git blame -w` on the whole file | 58284 |
| `git blame -w -L240,270` | 3373 |
| `git-why internal/importpolicy/importpolicy.go 240-270` | 1477 |

Blame returns a sha, an author, a date and a copy of the source. The reader
already has the source. The reader wants the reason, and blame never prints
it.

**A reflow commit masks the real reason.** In the same repository,
`git blame -w docs/decisions/pub-pipeline-repo-publication.md:421` returns
commit `6067b07f`, whose subject is `style: Split the longest sentences this
branch adds`. That subject explains nothing about the line. House style caps
a sentence at 25 words, so this repository produces reflow commits as normal
work. `-w` does not help, because the words moved between lines.

`git-why` reads `.git-blame-ignore-revs`, so a listed reflow commit steps
aside and the real reason appears.

## Install

The tool is one POSIX shell script. It needs `git` and standard userland.
There is no build step and no other dependency.

```sh
git clone <this repository> ~/src/git-why
ln -s ~/src/git-why/git-why /usr/local/bin/git-why
```

Git finds any `git-*` file on `PATH`, so `git why` also works.

## Use

```sh
git-why internal/cli/cli.go 240-270   # the reasons behind lines 240 to 270
git-why internal/cli/cli.go 421       # the reason behind one line
git-why internal/cli/cli.go           # rank the commits, print no bodies
```

Whole file mode prints one line per commit and no body. A whole file question
asks for a map, not for a reason.

| option | meaning |
| --- | --- |
| `-n N` | Print the body of the first N commits. Default 3. |
| `-b N` | Print a maximum of N body lines per commit. Default 20. |
| `--ignore-revs-file F` | Ignore the commits that file F lists. |
| `-h`, `--help` | Print the help. |

Exit codes: `0` success, `1` bad usage, `2` git failed or the file or the
range is wrong.

### What it does under the hood

`git blame -w -C -C -C --porcelain`. `-w` hides whitespace edits. `-C -C -C`
follows moved and copied lines. A reformat or a code move must not become the
answer.

It then counts the lines of each commit with a map keyed on the sha. One
commit counts once, even when it owns two blocks that do not touch. It ranks
the commits by that count. It breaks a tie by first appearance in the range.

## The caps, and the numbers behind them

The tool exists to cut the cost of a question. An answer with no limit would
undo that. Two caps hold the size, and the tool always names what it cut.

**`-n 3`, the number of commits it opens.** Across 295 sampled 30 line ranges
in the orchestrator repository, a range holds 3 commits at the median and 3.3
at the mean. The three highest ranked commits explain 94% of the lines at the
mean, and 80% or more of the lines in 92% of the ranges. Three commits answer
the question for most ranges. The tool still names every commit it did not
open, with its line count and its subject, so nothing disappears.

**`-b 20`, the body lines per commit.** Across 489 commits in the same
repository, a body runs 17 lines at the median and 19.7 at the mean. A cap of
20 prints 61% of bodies whole and covers the median body. It also holds the
worst case to 60 body lines. A commit body states its problem first and its
detail second, so a cut body keeps the part that answers "why".

Every cut prints its own notice and the command that reads the rest, either
`git log -1 <sha>` or a longer `git-why`. A silent cut reads as a complete
answer, which is worse than no answer.

Raise either cap when you need the whole record: `git-why -n 10 -b 200 <file>
<range>`.

## The `.git-blame-ignore-revs` convention

The file lists commits that blame must look through. Each line holds one full
40 character sha. A line that starts with `#` is a comment.

**Add a commit when it changes the shape of the text and none of the
meaning.** A reflow, a re-indent, a formatter run, an import sort and a quote
style change all qualify.

**Do not add a commit that changes behaviour or wording.** If a reader could
ask "why does it say that now", the commit holds a reason, and blame must
keep pointing at it. If in doubt, leave the commit out. A missing entry costs
one extra lookup. A wrong entry hides a real reason forever.

Write the commit so this stays easy. Keep a reflow in its own commit and
change nothing else in it. A commit that reflows and edits at the same time
cannot go in the file, and it masks its own reason.

Three readers use the file:

- **git**, once you point config at it. Run this once per clone:
  `git config blame.ignoreRevsFile .git-blame-ignore-revs`
- **GitHub**, which reads it from the repository root with no config.
- **git-why**, which reads the root file too when no config names one, so the
  agent and the web page give the same answer.

## Tests

```sh
./test.sh
```

The script builds a git repository under `mktemp` with a known history, then
it asserts the output. It reads no configuration from the machine, and it
touches no other repository. It exits non-zero on any failure.

It covers a line with one reason, a range across two commits, and a commit
that owns two separate blocks. It also covers a reflow commit that the ignore
file hides, and a moved block of code. It checks both cap notices, whole file
mode, and every error path.

## License

MIT. See [LICENSE](LICENSE).
