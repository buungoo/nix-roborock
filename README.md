# nix-roborock

Nix packaging and a reusable NixOS service module for Roborock Local Server.
The non-flake `upstream` input currently points to the sibling
`local_roborock_server` checkout, including its IPv6 changes. The application
and its tests are built directly from that source; no duplicate patch is applied.
The input can later point to the application's remote repository.

uv2nix builds the Python 3.13 environment from upstream's `uv.lock`.
`packages.<system>.default` exports the application;
`nixosModules.default` exports `services.roborock-local-server`.

## Service configuration

The module accepts upstream TOML settings through `settings` and four runtime
secret paths through `credentialFiles`:

```nix
services.roborock-local-server = {
  enable = true;
  credentialFiles = {
    admin-password = "/run/secrets/roborock/admin-password";
    protocol-login-email = "/run/secrets/roborock/protocol-login-email";
    protocol-login-pin = "/run/secrets/roborock/protocol-login-pin";
    session-secret = "/run/secrets/roborock/session-secret";
  };
  settings = {
    network = {
      stack_fqdn = "api-roborock.example.com";
      bind_host = "::";
      listener_mode = "external_tls";
      advertised_https_port = 443;
      advertised_mqtt_tls_port = 8883;
    };
    tls.mode = "provided";
  };
};
```

systemd supplies the secrets with `LoadCredential`. The module renders a
mode-0600 working configuration, hashes the password and PIN, and preserves
dashboard switches across restarts. It does not generate credentials. Use
sops-nix or another runtime secret provider; secret values never enter the
Nix store. A single trailing newline in a credential file is ignored.

State defaults to `/var/lib/roborock-local-server`. Container networking,
proxy configuration and persistent mounts belong to the consuming configuration.

```sh
nix build
nix build .#checks.x86_64-linux.upstream .#checks.x86_64-linux.module
```
