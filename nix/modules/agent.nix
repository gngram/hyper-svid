{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hyper-svid.agent;
  shared = config.services.hyper-svid;
in {
  options.services.hyper-svid.agentPort = lib.mkOption {
    type = lib.types.port;
    default = 901;
    description = "The vsock port the agent binds/dials from.";
  };

  options.services.hyper-svid.agent = {
    enable = lib.mkEnableOption "Hyper-SVID Agent";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The hyper-svid package to use.";
    };

    settings = lib.mkOption {
      type = (pkgs.formats.json {}).type;
      default = {};
      description = "Configuration for the agent, mapped directly to `agent.json`. Detailed documentation is available at [docs/agent_configuration.md](../../docs/agent_configuration.md) and sample file at [config-examples/agent.json](../../config-examples/agent.json).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    services.udev.extraRules = ''
      KERNEL=="vsock", TAG+="systemd"
    '';

    environment.etc."hyper-svid/agent.json".source = (pkgs.formats.json {}).generate "agent.json" ({
        vm_name = config.networking.hostName;
      }
      // cfg.settings
      // {
        client_port = shared.agentPort;
      });

    systemd.services.hyper-svid-agent = {
      description = "Hyper-SVID Agent";
      # Anchor to early boot instead of normal multi-user startup
      wantedBy = ["sysinit.target"];
      unitConfig = {
        DefaultDependencies = false;
      };
      bindsTo = ["dev-vsock.device"];
      after = ["dev-vsock.device"];
      before = ["sysinit.target"];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/hyper-svid-agent --config /etc/hyper-svid/agent.json";
        Restart = "always";
      };
    };
  };
}
