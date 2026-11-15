"""
ANSI terminal styling and diagnostic print helpers.
Part of the Debian Dev Suite.
"""

# ANSI Color codes
BOLD = "\033[1m"
GREEN = "\033[0;32m"
CYAN = "\033[0;36m"
YELLOW = "\033[1;33m"
RED = "\033[0;31m"
MAGENTA = "\033[0;35m"
RESET = "\033[0m"


def print_pass(msg: str) -> None:
    """Print success message with green checkmark."""
    print(f"  {GREEN}[✔]{RESET} {msg}")


def print_info(msg: str) -> None:
    """Print informational message with cyan icon."""
    print(f"  {CYAN}[ℹ]{RESET} {msg}")


def print_warn(msg: str) -> None:
    """Print warning message with yellow alert icon."""
    print(f"  {YELLOW}[⚠]{RESET} {msg}")


def print_fail(msg: str) -> None:
    """Print failure message with red cross."""
    print(f"  {RED}[✘]{RESET} {msg}")


def print_header(title: str) -> None:
    """Print a visually distinct banner header."""
    print()
    print(f"{CYAN}{BOLD}{'=' * 78}{RESET}")
    print(f"{CYAN}{BOLD}  {title}{RESET}")
    print(f"{CYAN}{BOLD}{'=' * 78}{RESET}")
    print()

