# Contributing

Thank you for reading this before you open a pull request.

## The rules

- **Rebase merges only.** Squash and merge commits are disabled. The history of
  this repository is a record of decisions, and a squashed feature answers
  "why is this line here" with one message about everything.
- **One coherent decision per commit.** Split a branch by decision, not by file.
- **The commit message explains WHY, not what.** The diff already says what
  changed. The message says what problem it solves, and what the alternative
  was. Anyone can read `git-why` to see the standard this repository holds
  itself to.
- **The subject line is imperative and short.** Under about 70 characters.
- **Tests pass.** Run `./test.sh`. It builds a fixture repository, so it needs
  no network and touches nothing outside a temporary directory.
- **New behaviour needs a test.** Add it to `test.sh` beside the others.

## Prose style

Sentences are short, active, and carry one meaning. Avoid idioms. This applies
to the README, to comments, and to commit messages.

## Reformatting commits

A commit that only reflows or reformats, and changes no meaning, must be added
to `.git-blame-ignore-revs` in a follow-up commit. Otherwise it MASKS the real
reason in `git blame`, which is the exact problem this tool exists to solve.

## Signed commits

Commits to `main` must be signed. GitHub documents how to sign with an SSH key,
which needs no GPG setup.

## Scope

This tool stays small. Its purpose is to answer one question cheaply. A feature
that adds output, adds a dependency, or adds a build step works against that,
and needs a strong argument.
