import importlib.util
import json
from pathlib import Path
import stat
import tomllib

import pytest

from roborock_local_server.security import verify_password

spec = importlib.util.spec_from_file_location("bootstrap", Path(__file__).parents[1] / "bootstrap.py")
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


@pytest.fixture
def configuration(tmp_path, monkeypatch):
    base = tmp_path / "base.toml"
    base.write_text('''
[network]
stack_fqdn = "api-roborock.example.com"
bind_host = "::"
listener_mode = "external_tls"
[tls]
mode = "provided"
''')
    defaults = tmp_path / "defaults.json"
    defaults.write_text("{}")
    state = tmp_path / "state"
    state.mkdir(mode=0o700)
    credentials = tmp_path / "credentials"
    credentials.mkdir(mode=0o700)
    for name, value in {
        "admin-password": 'a "quoted" password with \\slashes and spaces',
        "protocol-login-email": "local@example.com",
        "protocol-login-pin": "000123\n",
        "session-secret": "a-session-secret-longer-than-24-characters",
    }.items():
        (credentials / name).write_text(value)
    monkeypatch.setenv("CREDENTIALS_DIRECTORY", str(credentials))
    return base, defaults, state, credentials


def test_runtime_credentials_are_encoded_and_passwords_not_persisted(configuration):
    base, defaults, state, credentials = configuration
    bootstrap.configure(base, defaults, state)
    text = (state / "config.toml").read_text()
    admin = tomllib.loads(text)["admin"]
    assert verify_password((credentials / "admin-password").read_text(), admin["password_hash"])
    assert verify_password("000123", admin["protocol_login_pin_hash"])
    assert admin["protocol_login_email"] == "local@example.com"
    assert stat.S_IMODE((state / "config.toml").stat().st_mode) == 0o600
    assert "000123" not in text
    assert list(state.iterdir()) == [state / "config.toml"]


def test_restart_preserves_session_identity_and_dashboard_switch(configuration):
    base, defaults, state, _ = configuration
    bootstrap.configure(base, defaults, state)
    config = state / "config.toml"
    config.write_text(config.read_text().replace("new_connections_enabled = true", "new_connections_enabled = false"))
    before = tomllib.loads(config.read_text())["admin"]
    bootstrap.configure(base, defaults, state)
    after = tomllib.loads(config.read_text())["admin"]
    assert after["session_secret"] == before["session_secret"]
    assert after["new_connections_enabled"] is False
    assert verify_password("000123", after["protocol_login_pin_hash"])


@pytest.mark.parametrize("field,value", [("protocol-login-pin", "12345"), ("session-secret", "short")])
def test_invalid_credentials_leave_working_configuration_intact(configuration, field, value):
    base, defaults, state, credentials = configuration
    bootstrap.configure(base, defaults, state)
    before = (state / "config.toml").read_bytes()
    (credentials / field).write_text(value)
    with pytest.raises(ValueError):
        bootstrap.configure(base, defaults, state)
    assert (state / "config.toml").read_bytes() == before
    assert list(state.iterdir()) == [state / "config.toml"]
