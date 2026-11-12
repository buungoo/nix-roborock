"""Render upstream config from Nix settings and systemd runtime credentials."""

import json
import os
from pathlib import Path
import sys
import tempfile
import tomllib

from roborock_local_server.config import load_config
from roborock_local_server.security import hash_password


def configure(base_file, defaults_file, state_dir):
    state_dir = Path(state_dir)
    config_file = state_dir / "config.toml"
    admin = {}
    if config_file.exists():
        admin.update(tomllib.loads(config_file.read_text())["admin"])
    admin.update(json.loads(Path(defaults_file).read_text()))

    credentials = Path(os.environ["CREDENTIALS_DIRECTORY"])

    def secret(name):
        return (credentials / name).read_text().removesuffix("\n")

    pin = secret("protocol-login-pin")
    if len(pin) != 6 or not pin.isascii() or not pin.isdigit():
        raise ValueError("protocol-login-pin must be a six-digit string")
    password = secret("admin-password")
    if not password:
        raise ValueError("admin-password must not be empty")
    admin.update(
        password_hash=hash_password(password),
        protocol_login_email=secret("protocol-login-email"),
        protocol_login_pin_hash=hash_password(pin),
        session_secret=secret("session-secret"),
    )
    admin.setdefault("protocol_auth_enabled", True)
    admin.setdefault("new_connections_enabled", True)
    admin.setdefault("session_ttl_seconds", 86400)

    def toml_value(value):
        if isinstance(value, (str, bool, int)):
            return json.dumps(value, ensure_ascii=True)
        raise TypeError(f"Unsupported admin setting: {type(value).__name__}")

    text = Path(base_file).read_text().rstrip() + "\n\n[admin]\n"
    text += "".join(f"{key} = {toml_value(value)}\n" for key, value in sorted(admin.items()))
    # Validate before atomically replacing a working configuration. The temporary
    # and final config are mode 0600; raw passwords/PINs are never persisted.
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=state_dir, delete=False) as out:
        temporary = Path(out.name)
        try:
            out.write(text)
            out.flush()
            os.fsync(out.fileno())
            load_config(temporary)
            os.replace(temporary, config_file)
        finally:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    configure(*sys.argv[1:])
