{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.roborock-local-server;
  format = pkgs.formats.toml {};
  baseConfig = format.generate "roborock-local-server.toml" (lib.removeAttrs cfg.settings ["admin"]);
  adminDefaults = pkgs.writeText "roborock-admin-defaults.json" (builtins.toJSON (cfg.settings.admin or {}));
in {
  options.services.roborock-local-server = {
    enable = lib.mkEnableOption "Roborock Local Server";
    package = lib.mkOption {
      type = lib.types.package;
      description = "Server package exported by nix-roborock (including its venv passthru).";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "roborock-local-server";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "roborock-local-server";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/roborock-local-server";
    };
    credentialFiles = lib.mkOption {
      type = lib.types.submodule {
        options = lib.genAttrs ["admin-password" "protocol-login-email" "protocol-login-pin" "session-secret"] (_:
          lib.mkOption {
            type = lib.types.str;
            description = "Runtime secret file passed to the service through systemd credentials.";
          });
      };
      description = "Runtime credential files, for example paths provided by sops-nix.";
    };
    settings = lib.mkOption {
      type = format.type;
      default = {};
      description = "Non-secret upstream configuration. Admin hashes and the session secret are supplied at runtime.";
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(lib.any (key: builtins.hasAttr key (cfg.settings.admin or {})) ["password_hash" "session_secret" "protocol_login_pin_hash"]);
        message = "Use services.roborock-local-server.credentialFiles for credentials, keeping secrets out of the Nix store.";
      }
    ];

    services.roborock-local-server.settings = {
      network = {
        bind_host = lib.mkDefault "::";
        https_port = lib.mkDefault 555;
        mqtt_tls_port = lib.mkDefault 8881;
      };
      storage.data_dir = lib.mkDefault cfg.stateDirectory;
      broker = {
        mode = lib.mkDefault "embedded";
        host = lib.mkDefault "127.0.0.1";
        port = lib.mkDefault 18830;
        mosquitto_binary = lib.mkDefault (lib.getExe pkgs.mosquitto);
        enable_topic_bridge = lib.mkDefault true;
      };
      tls.mode = lib.mkDefault "provided";
      turn.mode = lib.mkDefault "disabled";
    };

    users.groups.${cfg.group} = {};
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
    };

    systemd.services.roborock-local-server = {
      description = "Local Roborock HTTPS and MQTT server";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target"];
      restartTriggers = [baseConfig adminDefaults];
      serviceConfig = {
        ExecStartPre = "${cfg.package.venv}/bin/python ${./bootstrap.py} ${baseConfig} ${adminDefaults} ${lib.escapeShellArg cfg.stateDirectory}";
        ExecStart = "${lib.getExe cfg.package} serve --config ${cfg.stateDirectory}/config.toml";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDirectory;
        StateDirectory = lib.removePrefix "/var/lib/" cfg.stateDirectory;
        StateDirectoryMode = "0700";
        UMask = "0077";
        LoadCredential = lib.mapAttrsToList (name: path: "${name}:${path}") cfg.credentialFiles;
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStopSec = 30;
        AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
        CapabilityBoundingSet = ["CAP_NET_BIND_SERVICE"];
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictRealtime = true;
        LockPersonality = true;
        RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.settings.network.https_port cfg.settings.network.mqtt_tls_port];
  };
}
