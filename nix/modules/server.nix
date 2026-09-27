{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hyper-svid.server;
  shared = config.services.hyper-svid;
in {
  options.services.hyper-svid.serverPort = lib.mkOption {
    type = lib.types.port;
    default = 900;
    description = "The vsock port the server listens on.";
  };

  options.services.hyper-svid.server = {
    enable = lib.mkEnableOption "Hyper-SVID Server";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The hyper-svid package to use.";
    };

    settings = lib.mkOption {
      type = (pkgs.formats.json {}).type;
      default = {};
      description = "Configuration for the server, mapped directly to `host.json`. Detailed documentation is available at [docs/server_configuration.md](../../docs/server_configuration.md) and sample file at [config-examples/host.json](../../config-examples/host.json).";
    };

    generateKey = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to generate the CA key on startup (using --genkey).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    services.udev.extraRules = ''
      KERNEL=="vsock", TAG+="systemd"
    '';

    environment.etc."hyper-svid/host.json".source = (pkgs.formats.json {}).generate "host.json" (cfg.settings
      // {
        server_port = shared.serverPort;
      });

    systemd.services.hyper-svid-server = {
      description = "Hyper-SVID Host Server";
      wantedBy = ["sysinit.target"];
      unitConfig = {
        DefaultDependencies = false;
      };
      bindsTo = ["dev-vsock.device"];
      after = ["dev-vsock.device"];
      before = ["sysinit.target"];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/hyper-svid-server --config /etc/hyper-svid/host.json${lib.optionalString cfg.generateKey " --genkey"}";
        Restart = "always";
      };
    };
  };
}
