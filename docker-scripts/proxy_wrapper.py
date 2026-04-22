#!/usr/bin/env python3
"""
Proxy wrapper — blocks destructive subcommands and applies custom handlers inside Docker.
Installed as /usr/local/bin/<cmd> (takes priority over /usr/bin/<cmd> in PATH).
Real binary is called directly without sudo.

Every gated command makes effect only after appropriate symlinks created in /usr/local/bin.
Currentty, no symlinks created for : cat, ls. But support is kept here as examples.

Dispatch order:
  1. CUSTOM_HANDLERS registry  — per-command Python functions (cat, sed, …)
  2. Namespace rule engine      — subcommand/flag deny-lists (git, gh, …)
  3. Pass-through               — exec real binary unchanged

Configuration:
  CONFIG can be loaded from a JSON file at the path specified by PROXY_WRAPPER_CONFIG env var.
  If the file exists, it overrides the hardcoded defaults below.
  Set PROXY_WRAPPER_CONFIG=/path/to/config.json to use a custom config.
"""
import re
import subprocess
import sys
import os
import json
from typing import Callable

REAL_BINARY_DIR = "/usr/bin"
LS_SOURCE_PATH = "/x/y"
LS_TARGET_PATH = os.environ.get("WORKSPACE_ROOT", "/workspace")
PROXY_WRAPPER_CONFIG_PATH = os.environ.get("PROXY_WRAPPER_CONFIG", "/etc/proxy_wrapper_config.json")

_HARDCODED_CONFIG = {
    "namespaces": {
        "sqlite": {
            "paths": ["/workspace"],
            "git": {
                "denied_subcommands": {"rebase", "reset", "clean", "gc", "restore"},
                "denied_patterns":    [r"--force(?:-with-lease)?", r"-f\b"],
            },
            "gh": {
                "denied_subcommands": {"repo", "release", "secret", "auth"},
                "denied_patterns":    [],
            },
        },
    }
}

def _load_config() -> dict:
    """Load CONFIG from JSON file or return hardcoded defaults."""
    if os.path.isfile(PROXY_WRAPPER_CONFIG_PATH):
        try:
            with open(PROXY_WRAPPER_CONFIG_PATH, 'r') as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            print(f"[proxy_wrapper] warning: failed to load config from {PROXY_WRAPPER_CONFIG_PATH}: {e}", file=sys.stderr)
            return _HARDCODED_CONFIG
    return _HARDCODED_CONFIG

CONFIG = _load_config()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def match_namespace(cwd: str) -> dict | None:
    for ns in CONFIG["namespaces"].values():
        for path in ns["paths"]:
            if cwd == path or cwd.startswith(path + "/"):
                return ns
    return None


def _exec_real(called_as: str, args: list[str]) -> None:
    """Replace current process with the real binary — never returns."""
    real_binary = os.path.join(REAL_BINARY_DIR, called_as)
    os.execv(real_binary, [real_binary] + args)


def _block(msg: str) -> None:
    print(f"[proxy_wrapper] blocked: {msg}", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Custom command handlers
#
# Signature: handler(called_as, args, cwd, ns) -> None
#   called_as : basename the script was invoked as ("cat", "sed", …)
#   args      : sys.argv[1:]
#   cwd       : os.getcwd() at invocation time
#   ns        : matched namespace dict, or None if no namespace matched
#
# Each handler MUST either call _exec_real() (pass-through) or sys.exit().
# ---------------------------------------------------------------------------

def _cat_handler(called_as: str, args: list[str], cwd: str, ns: dict | None) -> None:
    """cat handler — files under WORKSPACE_ROOT are read via filter_content_by_context.

    Non-flag arguments that resolve to paths inside LS_TARGET_PATH (WORKSPACE_ROOT)
    are passed one-by-one to `filter_content_by_context <path>`.
    Everything else is handed to the real cat binary unchanged.
    """
    _ = ns
    workspace = LS_TARGET_PATH

    def _in_workspace(p: str) -> bool:
        resolved = os.path.normpath(p if os.path.isabs(p) else os.path.join(cwd, p))
        return resolved == workspace or resolved.startswith(workspace + "/")

    paths = [a for a in args if not a.startswith("-")]

    if any(_in_workspace(p) for p in paths):
        rc = 0
        for p in paths:
            resolved = os.path.normpath(p if os.path.isabs(p) else os.path.join(cwd, p))
            proc = subprocess.run(
                ["filter_content_by_context.py", resolved],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            sys.stdout.write(proc.stdout.decode(errors="replace"))
            sys.stderr.write(proc.stderr.decode(errors="replace"))
            rc = proc.returncode
        sys.exit(rc)

    _exec_real(called_as, args)


def _ls_handler(called_as: str, args: list[str], cwd: str, ns: dict | None) -> None:
    """ls handler — replaces LS_SOURCE_PATH with LS_TARGET_PATH in output.

    LS_SOURCE_PATH is the real on-disk root ("/x/y").
    LS_TARGET_PATH is read from the WORKSPACE_ROOT env var (default "/workspace").
    Outside a namespace the real binary is exec'd unchanged.
    """
    _ = (cwd, ns)
    # Rewrite path arguments: /workspace (LS_TARGET_PATH) -> /x/y (LS_SOURCE_PATH)
    def _rewrite_arg(a: str) -> str:
        norm = a.rstrip("/")
        if norm == LS_TARGET_PATH or norm.startswith(LS_TARGET_PATH + "/"):
            return LS_SOURCE_PATH + a[len(LS_TARGET_PATH):]
        return a

    args = [_rewrite_arg(a) for a in args]
    real_binary = os.path.join(REAL_BINARY_DIR, called_as)
    proc = subprocess.run([real_binary] + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    stdout = proc.stdout.decode(errors="replace").replace(LS_SOURCE_PATH, LS_TARGET_PATH)
    stderr = proc.stderr.decode(errors="replace").replace(LS_SOURCE_PATH, LS_TARGET_PATH)

    sys.stdout.write(stdout)
    sys.stderr.write(stderr)
    sys.exit(proc.returncode)


# Registry: map command basename -> handler function.
# Add entries here to intercept additional commands.
CUSTOM_HANDLERS: dict[str, Callable[[str, list[str], str, dict | None], None]] = {
    "cat": _cat_handler,
    "ls":  _ls_handler,
}


# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

def main() -> None:
    called_as = os.path.basename(sys.argv[0])
    args = sys.argv[1:]
    cwd = os.getcwd()
    ns = match_namespace(cwd)

    # 1. Custom handler dispatch
    handler = CUSTOM_HANDLERS.get(called_as)
    if handler is not None:
        handler(called_as, args, cwd, ns)
        return  # handler must exec or exit; this line is a safety fallback

    # 2. Namespace rule engine (subcommand / flag deny-lists)
    if ns is None:
        _exec_real(called_as, args)
        return

    rule = ns.get(called_as)
    if rule:
        subcommand = args[0] if args else ""
        if subcommand in rule["denied_subcommands"]:
            _block(f"'{called_as} {subcommand}' is not allowed in '{cwd}'.")

        args_str = " ".join(args)
        for pattern in rule["denied_patterns"]:
            if re.search(pattern, args_str):
                _block(f"forbidden flag pattern '{pattern}'.")

    # 3. Pass-through
    _exec_real(called_as, args)


if __name__ == "__main__":
    main()
