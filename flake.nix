{
  description = "Roborock Local Server: locked Python package and reusable NixOS service";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.zst";
    upstream = {
      url = "github:buungoo/local_roborock_server";
      flake = false;
    };
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    upstream,
    ...
  }: let
    inherit (nixpkgs) lib;
    forSystems = lib.genAttrs ["x86_64-linux" "aarch64-linux"];
    workspace = inputs.uv2nix.lib.workspace.loadWorkspace {workspaceRoot = upstream;};
    pythonSets = forSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      (pkgs.callPackage inputs.pyproject-nix.build.packages {python = pkgs.python313;}).overrideScope
      (lib.composeManyExtensions [
        inputs.pyproject-build-systems.overlays.wheel
        (workspace.mkPyprojectOverlay {sourcePreference = "wheel";})
        (final: prev: {
          roborock-local-server = prev.roborock-local-server.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or []) ++ final.resolveBuildSystem {hatchling = [];};
          });
        })
      ]));
  in {
    packages = forSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      pythonSet = pythonSets.${system};
      venv = pythonSet.mkVirtualEnv "roborock-local-server-env" workspace.deps.default;
      inherit (pkgs.callPackages inputs.pyproject-nix.build.util {}) mkApplication;
    in {
      default = self.packages.${system}.roborock-local-server;
      roborock-local-server =
        (mkApplication {
          inherit venv;
          package = pythonSet.roborock-local-server;
        }).overrideAttrs (old: {
          meta =
            (old.meta or {})
            // {
              description = "Local Roborock HTTPS and MQTT server with native IPv6 listeners";
              homepage = "https://github.com/Python-roborock/local_roborock_server";
              license = lib.licenses.mit;
              mainProgram = "roborock-local-server";
            };
          passthru = (old.passthru or {}) // {inherit venv;};
        });
    });

    nixosModules.default = {
      pkgs,
      lib,
      ...
    }: {
      imports = [./module.nix];
      services.roborock-local-server.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.default;
    };

    checks = forSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      pythonSet = pythonSets.${system};
      testEnv = pythonSet.mkVirtualEnv "roborock-local-server-test-env" workspace.deps.all;
    in
      import ./tests/checks.nix {
        inherit pkgs testEnv upstream;
        bootstrap = ./bootstrap.py;
      });

    formatter = forSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
  };
}
