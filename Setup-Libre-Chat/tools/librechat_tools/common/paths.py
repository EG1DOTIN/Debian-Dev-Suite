"""
Common path resolution utilities for LibreChat tools.
Part of the Debian Dev Suite (Zero Hardcoding Policy).
"""

import os
import pwd
import getpass
from pathlib import Path


def get_target_user() -> str:
    """Safely determines the invoking user under sudo or regular shell."""
    return os.environ.get("SUDO_USER") or os.environ.get("USER") or getpass.getuser()


def get_target_home() -> Path:
    """Safely resolves the home directory of the target user."""
    target_user = get_target_user()
    try:
        pw = pwd.getpwnam(target_user)
        return Path(pw.pw_dir)
    except Exception:
        return Path.home()


def get_librechat_base_dir() -> Path:
    """Resolves the canonical LibreChat installation directory (~/.local/share/dev-setups/librechat), or LIBRECHAT_DATA_DIR if set."""
    env_dir = os.environ.get("LIBRECHAT_DATA_DIR")
    if env_dir:
        return Path(env_dir).expanduser().resolve()
    return get_target_home() / ".local" / "share" / "dev-setups" / "librechat"


def get_librechat_images_dir() -> Path:
    """Resolves LibreChat's static images folder."""
    return get_librechat_base_dir() / "librechat-data" / "images"

