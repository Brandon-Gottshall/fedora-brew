#!/usr/bin/env python3
"""Keep packages shared between tap branches in parity, fully or partially.

Configuration lives in branch-parity.json at the repository root:

  {
    "branches": {
      "import-local-work": {"tap": "fedora-brew"},
      "linux-formulas/arch-support": {"tap": "linux-formulas"}
    },
    "packages": {
      "Formula/shadow-pc.rb": "full",
      "Formula/claude-desktop.rb": {"mode": "partial", "fields": ["url", "version", "sha256"]}
    }
  }

Each branch maps identity tokens to the strings that differ only because of
that branch's tap identity. Shared text is compared with those strings
abstracted away, then written back in each target branch's spelling.

  full     the whole file is kept identical (modulo identity tokens); a file
           missing on a branch is created there
  partial  only the listed top-level stanzas are kept identical; everything
           else may differ per branch

Package options: "branches" limits sharing to a subset of branches, "source"
pins the authoritative branch (otherwise the branch whose latest commit touched
the file wins, ties going to the first listed branch), and "rewrite": false
disables identity rewriting. Sync commits directly to the local branches
without switching the checkout; a branch checked out in a worktree has the
synced paths refreshed there.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

CONFIG_NAME = "branch-parity.json"
DEFAULT_FIELDS = ("url", "version", "sha256")
MODES = ("full", "partial")
PLACEHOLDER_RE = re.compile(r"\{\{parity:([A-Za-z0-9_-]+)\}\}")


class ParityError(Exception):
    pass


@dataclass(frozen=True)
class Package:
    path: str
    mode: str
    branches: tuple[str, ...]
    fields: tuple[str, ...] = ()
    source: str | None = None
    rewrite: bool = True

    def describe(self) -> str:
        return f"partial: {', '.join(self.fields)}" if self.mode == "partial" else "full"


@dataclass(frozen=True)
class Config:
    identities: dict[str, dict[str, str]]
    packages: tuple[Package, ...]

    def tokens(self, package: Package, branch: str) -> dict[str, str]:
        return self.identities[branch] if package.rewrite else {}


@dataclass(frozen=True)
class Update:
    text: str
    summary: str


@dataclass
class Plan:
    package: Package
    source: str | None = None
    updates: dict[str, Update] = field(default_factory=dict)
    problems: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


class Repo:
    def __init__(self, root: Path, remote: str | None = None):
        self.root = root
        self.remote = remote

    def git(self, *args: str, input: str | None = None, env: dict | None = None,
            cwd: Path | None = None, check: bool = True) -> str:
        result = subprocess.run(
            ["git", "-C", str(cwd or self.root), *args],
            input=input, env=env, capture_output=True, text=True,
        )
        if check and result.returncode != 0:
            raise ParityError(f"git {' '.join(args)}: {result.stderr.strip()}")
        return result.stdout

    def ref(self, branch: str) -> str:
        return f"refs/remotes/{self.remote}/{branch}" if self.remote else f"refs/heads/{branch}"

    def has_branch(self, branch: str) -> bool:
        return bool(self.git("rev-parse", "--verify", "--quiet", self.ref(branch), check=False).strip())

    def read(self, branch: str, path: str) -> str | None:
        result = subprocess.run(
            ["git", "-C", str(self.root), "cat-file", "blob", f"{self.ref(branch)}:{path}"],
            capture_output=True,
        )
        return result.stdout.decode() if result.returncode == 0 else None

    def files(self, branch: str, prefixes: list[str]) -> set[str]:
        return set(self.git("ls-tree", "-r", "--name-only", self.ref(branch), "--", *prefixes).split("\n")) - {""}

    def touched_at(self, branch: str, path: str) -> int:
        return int(self.git("log", "-1", "--format=%ct", self.ref(branch), "--", path).strip() or 0)

    def behind_upstream(self, branch: str) -> int:
        upstream = self.git("rev-parse", "--verify", "--quiet", f"{branch}@{{upstream}}", check=False).strip()
        if not upstream:
            return 0
        return int(self.git("rev-list", "--count", f"refs/heads/{branch}..{upstream}").strip())

    def worktrees(self) -> dict[str, Path]:
        checked_out, worktree = {}, None
        for line in self.git("worktree", "list", "--porcelain").splitlines():
            if line.startswith("worktree "):
                worktree = Path(line.removeprefix("worktree "))
            elif line.startswith("branch refs/heads/") and worktree is not None:
                checked_out[line.removeprefix("branch refs/heads/")] = worktree
        return checked_out

    def commit(self, branch: str, files: dict[str, str], message: str) -> str:
        ref = f"refs/heads/{branch}"
        tip = self.git("rev-parse", ref).strip()
        with tempfile.TemporaryDirectory(prefix="branch-parity-") as temporary:
            env = {**os.environ, "GIT_INDEX_FILE": str(Path(temporary) / "index")}
            self.git("read-tree", tip, env=env)
            for path, text in files.items():
                blob = self.git("hash-object", "-w", "--stdin", input=text).strip()
                listing = self.git("ls-tree", tip, "--", path).split()
                mode = listing[0] if listing else "100644"
                self.git("update-index", "--add", "--cacheinfo", f"{mode},{blob},{path}", env=env)
            tree = self.git("write-tree", env=env).strip()
        commit = self.git("commit-tree", tree, "-p", tip, "-m", message).strip()
        self.git("update-ref", "-m", "branch-parity: sync", ref, commit, tip)
        return commit


def load_config(path: Path) -> Config:
    try:
        raw = json.loads(path.read_text())
    except FileNotFoundError:
        raise ParityError(f"{path} not found") from None
    except json.JSONDecodeError as error:
        raise ParityError(f"{path}: {error}") from None

    identities = raw.get("branches")
    if not isinstance(identities, dict) or len(identities) < 2:
        raise ParityError("config must list at least two branches")
    for branch, tokens in identities.items():
        if not isinstance(tokens, dict) or not all(isinstance(v, str) and v for v in tokens.values()):
            raise ParityError(f"branch {branch}: identity tokens must map names to non-empty strings")
        if len(set(tokens.values())) != len(tokens):
            raise ParityError(f"branch {branch}: identity token values must be distinct")
    if len({tuple(sorted(tokens)) for tokens in identities.values()}) > 1:
        raise ParityError("every branch must define the same identity token names")

    packages = []
    for path, spec in raw.get("packages", {}).items():
        spec = {"mode": spec} if isinstance(spec, str) else spec
        mode = spec.get("mode", "full")
        if mode not in MODES:
            raise ParityError(f"{path}: mode must be one of {', '.join(MODES)}")
        if mode == "full" and "fields" in spec:
            raise ParityError(f"{path}: fields only apply to partial packages")
        branches = tuple(spec.get("branches", identities))
        unknown = set(branches) - identities.keys()
        if unknown:
            raise ParityError(f"{path}: unknown branches {', '.join(sorted(unknown))}")
        if len(branches) < 2:
            raise ParityError(f"{path}: a shared package needs at least two branches")
        fields = tuple(spec.get("fields", DEFAULT_FIELDS)) if mode == "partial" else ()
        if mode == "partial" and not fields:
            raise ParityError(f"{path}: partial packages need at least one field")
        source = spec.get("source")
        if source is not None and source not in branches:
            raise ParityError(f"{path}: source {source} is not one of its branches")
        packages.append(Package(path, mode, branches, fields, source, bool(spec.get("rewrite", True))))
    return Config(identities, tuple(packages))


def abstract(text: str, tokens: dict[str, str]) -> str:
    if not tokens:
        return text
    names = {value: name for name, value in tokens.items()}
    pattern = re.compile("|".join(re.escape(value) for value in sorted(names, key=len, reverse=True)))
    return pattern.sub(lambda match: f"{{{{parity:{names[match.group(0)]}}}}}", text)


def concretize(text: str, tokens: dict[str, str]) -> str:
    return PLACEHOLDER_RE.sub(lambda match: tokens.get(match.group(1), match.group(0)), text)


def translate(text: str, source_tokens: dict[str, str], target_tokens: dict[str, str]) -> str:
    neutral = abstract(text, source_tokens)
    result = concretize(neutral, target_tokens)
    # Text that already spells the target's identity cannot round-trip; refuse
    # rather than silently rewriting something that was meant literally.
    if abstract(result, target_tokens) != neutral:
        raise ParityError("identity rewrite is ambiguous (source already contains the target's spelling)")
    return result


def stanza(text: str, name: str) -> tuple[int, int] | None:
    """Span of the first top-level `  name ...` stanza, including `,` continuations."""
    match = re.search(rf"^  {re.escape(name)}(?=[ (]|$)", text, re.MULTILINE)
    if match is None:
        return None
    start = match.start()
    end = text.find("\n", start)
    end = len(text) if end == -1 else end
    while text[start:end].rstrip().endswith(",") and end < len(text):
        following = text.find("\n", end + 1)
        end = len(text) if following == -1 else following
    return start, end


def merge_fields(target: str, source: str, fields: tuple[str, ...], source_branch: str,
                 source_tokens: dict[str, str], target_tokens: dict[str, str]) -> tuple[str, list[str], list[str]]:
    result, changed, problems = target, [], []
    for name in fields:
        wanted, current = stanza(source, name), stanza(result, name)
        if wanted is None and current is None:
            continue
        if wanted is None or current is None:
            owner = source_branch if current is None else "target"
            problems.append(f"top-level `{name}` exists on {owner} only")
            continue
        value = translate(source[wanted[0]:wanted[1]], source_tokens, target_tokens)
        if result[current[0]:current[1]] != value:
            result = result[:current[0]] + value + result[current[1]:]
            changed.append(name)
    return result, changed, problems


def plan_package(repo: Repo, config: Config, package: Package, forced_source: str | None = None) -> Plan:
    plan = Plan(package)
    if forced_source and forced_source not in package.branches:
        plan.notes.append(f"not shared with {forced_source}; skipped")
        return plan

    texts = {}
    for branch in package.branches:
        if repo.has_branch(branch):
            texts[branch] = repo.read(branch, package.path)
        else:
            plan.problems.append(f"branch {repo.ref(branch)} does not exist")
    present = [branch for branch, text in texts.items() if text is not None]
    if not present:
        plan.problems.append("missing on every branch")
        return plan

    source = forced_source or package.source
    if source is None:
        source = max(present, key=lambda b: (repo.touched_at(b, package.path), -package.branches.index(b)))
    elif texts.get(source) is None:
        plan.problems.append(f"source {source} does not have this file")
        return plan
    plan.source = source
    source_text, source_tokens = texts[source], config.tokens(package, source)

    for target, current in texts.items():
        if target == source:
            continue
        target_tokens = config.tokens(package, target)
        try:
            if package.mode == "full":
                desired = translate(source_text, source_tokens, target_tokens)
                summary = "create" if current is None else "content"
            elif current is None:
                plan.problems.append(f"{target}: file missing (partial packages are never created)")
                continue
            else:
                desired, changed, problems = merge_fields(
                    current, source_text, package.fields, source, source_tokens, target_tokens)
                plan.problems.extend(f"{target}: {problem}" for problem in problems)
                summary = ", ".join(changed)
        except ParityError as error:
            plan.problems.append(f"{target}: {error}")
            continue
        if desired != current:
            plan.updates[target] = Update(desired, summary)
    return plan


def report(plans: list[Plan]) -> None:
    for plan in plans:
        status = "error" if plan.problems else "drift" if plan.updates else "ok"
        print(f"{status:<6} {plan.package.path} ({plan.package.describe()})")
        for target, update in plan.updates.items():
            print(f"         {target}: {update.summary} <- {plan.source}")
        for line in plan.problems + plan.notes:
            print(f"         {line}")


def apply(repo: Repo, plans: list[Plan]) -> dict[str, str]:
    by_branch: dict[str, dict[str, str]] = {}
    origins: dict[str, list[Plan]] = {}
    for plan in plans:
        for target, update in plan.updates.items():
            by_branch.setdefault(target, {})[plan.package.path] = update.text
            origins.setdefault(target, []).append(plan)

    checked_out = repo.worktrees()
    for branch, files in by_branch.items():
        behind = repo.behind_upstream(branch)
        if behind:
            raise ParityError(f"{branch} is {behind} commit(s) behind its upstream; pull it first")
        if branch in checked_out and repo.git("status", "--porcelain", "--", *files, cwd=checked_out[branch]).strip():
            raise ParityError(f"{branch} has local changes to {', '.join(files)} in {checked_out[branch]}")

    commits = {}
    for branch, files in by_branch.items():
        sources = origins[branch]
        if len(sources) == 1:
            subject = f"Sync {sources[0].package.path} from {sources[0].source}"
        else:
            subject = "Sync shared packages from other branches"
        body = "\n".join(f"- {p.package.path} ({p.package.describe()}) from {p.source}" for p in sources)
        commits[branch] = repo.commit(branch, files, f"{subject}\n\n{body}")
        if branch in checked_out:
            repo.git("checkout", "HEAD", "--", *files, cwd=checked_out[branch])
    return commits


def suggest(repo: Repo, config_path: Path, prefixes: list[str]) -> dict:
    raw = json.loads(config_path.read_text()) if config_path.exists() else {}
    identities = raw.get("branches")
    if not isinstance(identities, dict) or len(identities) < 2:
        raise ParityError(f"add at least two branches (with identity tokens) to {config_path} first")
    branches = [branch for branch in identities if repo.has_branch(branch)]
    files = {branch: repo.files(branch, prefixes) for branch in branches}
    packages = dict(raw.get("packages", {}))
    for path in sorted(set().union(*files.values())):
        holders = [branch for branch in branches if path in files[branch]]
        if path in packages or len(holders) < 2:
            continue
        texts = {branch: repo.read(branch, path) for branch in holders}
        if len({abstract(texts[b], identities[b]) for b in holders}) == 1:
            spec: dict = {"mode": "full"}
        else:
            common = [name for name in DEFAULT_FIELDS if all(stanza(t, name) for t in texts.values())]
            if not common:
                print(f"skip {path}: differs and shares none of {', '.join(DEFAULT_FIELDS)}", file=sys.stderr)
                continue
            spec = {"mode": "partial", "fields": common}
        if holders != list(identities):
            spec["branches"] = holders
        packages[path] = "full" if spec == {"mode": "full"} else spec
    return {**raw, "packages": packages}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--config", type=Path, help=f"defaults to <repo>/{CONFIG_NAME}")
    commands = parser.add_subparsers(dest="command", required=True)

    check = commands.add_parser("check", help="report drift; exits 1 when anything is out of parity")
    check.add_argument("--remote", help="compare <remote>/<branch> instead of local branches")
    sync = commands.add_parser("sync", help="commit parity fixes to the local branches")
    sync.add_argument("--push", metavar="REMOTE", nargs="?", const="origin",
                      help="push updated branches afterwards (default remote: origin)")
    for command in (check, sync):
        command.add_argument("--from", dest="source", metavar="BRANCH", help="treat BRANCH as authoritative")
        command.add_argument("packages", nargs="*", help="limit to these package paths")
    proposal = commands.add_parser("suggest", help="propose config entries for packages on several branches")
    proposal.add_argument("--write", action="store_true", help="write the proposal back to the config")
    proposal.add_argument("prefixes", nargs="*", default=["Formula", "Casks"])
    args = parser.parse_args(argv)

    repo = Repo(args.repo.resolve(), getattr(args, "remote", None))
    config_path = args.config or repo.root / CONFIG_NAME

    if args.command == "suggest":
        proposal_text = json.dumps(suggest(repo, config_path, args.prefixes), indent=2) + "\n"
        if args.write:
            config_path.write_text(proposal_text)
            print(f"wrote {config_path}")
        else:
            print(proposal_text, end="")
        return 0

    config = load_config(config_path)
    if args.source and args.source not in config.identities:
        raise ParityError(f"--from {args.source} is not a configured branch")
    packages = config.packages
    if args.packages:
        known = {package.path: package for package in packages}
        missing = [path for path in args.packages if path not in known]
        if missing:
            raise ParityError(f"not in {config_path.name}: {', '.join(missing)}")
        packages = tuple(known[path] for path in args.packages)

    plans = [plan_package(repo, config, package, args.source) for package in packages]
    report(plans)
    failed = any(plan.problems for plan in plans)
    if args.command == "check":
        return 1 if failed or any(plan.updates for plan in plans) else 0

    commits = apply(repo, [plan for plan in plans if not plan.problems])
    for branch, commit in commits.items():
        print(f"committed {commit[:12]} to {branch}")
    if not commits:
        print("nothing to sync")
    if args.push and commits:
        repo.git("push", args.push, *commits)
        print(f"pushed {', '.join(commits)} to {args.push}")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ParityError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
