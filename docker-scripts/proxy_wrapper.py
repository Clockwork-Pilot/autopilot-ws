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
  If PROXY_WRAPPER_CONFIG env var is not set, all commands are allowed silently.
  If PROXY_WRAPPER_CONFIG is set, CONFIG is loaded from the JSON file at that path.
  Set PROXY_WRAPPER_CONFIG=/path/to/config.json to enforce restrictions.

Public API:
  is_command_allowed(called_as, args, cwd) -> (allowed: bool, reason: str | None)
    Pure check, used by external tooling (e.g. claude-plugin's bash hook) to
    ask "would proxy_wrapper let this through?" without actually running the
    command.

Example config:
{
    "namespaces": {
        "workspace": {
            "paths": ["/workspace"],
            "git": {
                "denied_subcommands": ["rebase", "reset", "clean", "gc", "restore"],
                "denied_patterns":    ["--force(?:-with-lease)?", "-f\\b"]
            },
            "sed": {
                "allowed_patterns":   ["-i"]
            }
        }
    }
}
"""
import re
import sys
import os
import json

REAL_BINARY_DIR = "/usr/bin"

def _load_config() -> dict:
    """Load CONFIG from JSON file if PROXY_WRAPPER_CONFIG env is defined.
    If env var not set, allow all commands silently."""
    config_path = os.environ.get("PROXY_WRAPPER_CONFIG")
    if not config_path:
        return {"namespaces": {}}
    if os.path.isfile(config_path):
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            print(f"[proxy_wrapper] warning: failed to load config from {config_path}: {e}", file=sys.stderr)
            return {"namespaces": {}}
    return {"namespaces": {}}

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

    args_str = " ".join(args)

    # If allowed_patterns exist, use allowlist mode: only allow if matches
    allowed_patterns = rule.get("allowed_patterns", [])
    if allowed_patterns:
        for pattern in allowed_patterns:
            if re.search(pattern, args_str):
                return True, None
        return False, f"{called_as}: command does not match allowed patterns."

    # Otherwise use blocklist mode: deny if matches denied patterns/subcommands
    subcommand = args[0] if args else ""
    if subcommand in rule.get("denied_subcommands", []):
        return False, f"'{called_as} {subcommand}' is not allowed in '{cwd}'."
    for pattern in rule.get("denied_patterns", []):
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


def _install_symlinks(wrapper_path: str, commands: list[str]) -> None:
    """Create symlinks for specified commands pointing to this wrapper.

    Example:
      python3 proxy_wrapper.py --install git gh chmod sed

    Creates:
      ln -sf /usr/local/bin/proxy_wrapper.py /usr/local/bin/git
      ...

    When these commands are called, proxy_wrapper intercepts them for
    namespace-scoped deny rules before passing to the real binary.
    """
    bin_dir = "/usr/local/bin"
    for cmd in commands:
        link_path = os.path.join(bin_dir, cmd)
        try:
            if os.path.lexists(link_path):
                print(f"[proxy_wrapper] warning: {link_path} already exists, skipping", file=sys.stderr)
                continue
            os.symlink(wrapper_path, link_path)
            print(f"[proxy_wrapper] installed: {link_path} -> {wrapper_path}")
        except OSError as e:
            print(f"[proxy_wrapper] error installing {cmd}: {e}", file=sys.stderr)
            sys.exit(1)


# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

def main() -> None:
    called_as = os.path.basename(sys.argv[0])
    args = sys.argv[1:]

    if called_as == "proxy_wrapper.py" and args and args[0] == "--install":
        commands = args[1:] if len(args) > 1 else ["git", "gh", "chmod", "sed"]
        wrapper_path = os.path.abspath(__file__)
        _install_symlinks(wrapper_path, commands)
        return

    cwd = os.getcwd()
    allowed, reason = is_command_allowed(called_as, args, cwd)
    if not allowed:
        _block(reason or "command not allowed")
    _exec_real(called_as, args)


if __name__ == "__main__":
    main()
