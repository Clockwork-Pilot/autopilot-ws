#!/usr/bin/env python3
"""
Proxy wrapper — applies namespace-scoped deny rules for git/gh/etc. inside Docker.
Installed as /usr/local/bin/<cmd> (takes priority over /usr/bin/<cmd> in PATH).
Real binary is called directly without sudo.

Every gated command takes effect only after appropriate symlinks are created in
/usr/local/bin pointing at this script.

Dispatch order (in main()):
  1. Namespace rule engine — subcommand/flag deny-lists (git, gh, …)
  2. Pass-through           — exec real binary unchanged

Configuration:
  CONFIG can be loaded from a JSON file at the path specified by PROXY_WRAPPER_CONFIG env var.
  If the file exists, it overrides the hardcoded defaults below.
  Set PROXY_WRAPPER_CONFIG=/path/to/config.json to use a custom config.

Public API:
  is_command_allowed(called_as, args, cwd) -> (allowed: bool, reason: str | None)
    Pure check, used by external tooling (e.g. claude-plugin's bash hook) to
    ask "would proxy_wrapper let this through?" without actually running the
    command.
"""
import re
import sys
import os
import json

REAL_BINARY_DIR = "/usr/bin"
PROXY_WRAPPER_CONFIG_PATH = os.environ.get("PROXY_WRAPPER_CONFIG", "/etc/proxy_wrapper_config.json")

_HARDCODED_CONFIG = {
    "namespaces": {
        "workspace": {
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


def is_command_allowed(called_as: str, args: list[str], cwd: str) -> tuple[bool, str | None]:
    """Return (allowed, reason).

    `reason` is non-None and human-readable when allowed=False. Pure function:
    safe to call from any caller (including the claude-plugin Bash hook) to
    ask "would this command pass the namespace deny rules?" without side
    effects.
    """
    ns = match_namespace(cwd)
    if ns is None:
        return True, None
    rule = ns.get(called_as)
    if not rule:
        return True, None
    subcommand = args[0] if args else ""
    if subcommand in rule["denied_subcommands"]:
        return False, f"'{called_as} {subcommand}' is not allowed in '{cwd}'."
    args_str = " ".join(args)
    for pattern in rule["denied_patterns"]:
        if re.search(pattern, args_str):
            return False, f"{called_as}: forbidden flag pattern '{pattern}'."
    return True, None


def _exec_real(called_as: str, args: list[str]) -> None:
    """Replace current process with the real binary — never returns."""
    real_binary = os.path.join(REAL_BINARY_DIR, called_as)
    os.execv(real_binary, [real_binary] + args)


def _block(msg: str) -> None:
    print(f"[proxy_wrapper] blocked: {msg}", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

def main() -> None:
    called_as = os.path.basename(sys.argv[0])
    args = sys.argv[1:]
    cwd = os.getcwd()

    allowed, reason = is_command_allowed(called_as, args, cwd)
    if not allowed:
        _block(reason or "command not allowed")
    _exec_real(called_as, args)


if __name__ == "__main__":
    main()
