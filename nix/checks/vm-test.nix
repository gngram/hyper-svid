{
  pkgs,
  nixosModules,
  hyperSvid,
  hyperSvidGo,
}: let
  testModule = {lib, ...}: {
    imports = [nixosModules.default];

    # We need vsock loopback support
    boot.kernelModules = ["vsock_loopback"];
    environment.systemPackages = [pkgs.time hyperSvidGo pkgs.openssl pkgs.swtpm pkgs.tpm2-tools];

    # CA Storage
    systemd.tmpfiles.rules = [
      "d /etc/hyper-svid/ca 0700 root root"
      "d /var/lib/service-a 0700 root root"
      "d /var/lib/service-b 0700 root root"
      "d /var/lib/service-c 0700 root root"
    ];

    users.groups.service-a.gid = 997;
    users.groups.service-b.gid = 998;
    users.groups.service-c.gid = 999;
    users.users.service-a = {
      isSystemUser = true;
      group = "service-a";
      uid = 997;
    };
    users.users.service-b = {
      isSystemUser = true;
      group = "service-b";
      uid = 998;
    };
    users.users.service-c = {
      isSystemUser = true;
      group = "service-c";
      uid = 999;
    };

    # Use our NixOS modules to configure hyper-svid
    services.hyper-svid.serverPort = 900;
    services.hyper-svid.agentPort = 901;
    services.hyper-svid.server = {
      enable = true;
      package = hyperSvid;
      generateKey = true;
      settings = {
        ca_cert_path = "/etc/hyper-svid/ca/ca-cert.pem";
        ca_key_path = "/etc/hyper-svid/ca/ca-key.pem";
        peer_port = 901;
        vms."local-vm" = {
          vm_cid = 1;
          ip = "127.0.0.1";
          attestation = {
            required = false;
          };
          identities = {
            service-a = {
              selector = "unix:user:service-a,unix:group:service-a,systemd:unitname:service-a";
              ttl_minutes = 1;
            };
            service-b = {
              selector = "unix:user:service-b,unix:group:service-b";
              ttl_minutes = 10;
            };
            service-c = {
              selector = "unix:user:service-c,unix:group:service-c";
              ttl_minutes = 10;
            };
          };
        };
      };
    };

    systemd.services.hyper-svid-agent.environment.VSOCK_HOST_CID = "1";

    services.hyper-svid.agent = {
      enable = true;
      package = hyperSvid;
      settings = {
        vm_name = "local-vm";
        server_port = 900;
        workload_api_socket = "/run/hyper-svid/workload.sock";
      };
    };

    # Disable auto-start of the agent during the test so we can run it manually
    systemd.services.hyper-svid-agent.wantedBy = lib.mkForce [];

    systemd.services.service-a = {
      description = "Service A Workload using Workload API";
      wantedBy = [];
      after = ["hyper-svid-agent.service"];
      serviceConfig = {
        ExecStart = "${hyperSvid}/bin/workload-test-workload /run/hyper-svid/workload.sock --test-rotation";
        User = "service-a";
        Group = "service-a";
        Type = "oneshot";
        PrivateTmp = false;
        Environment = "USER=service-a";
      };
    };
  };
in
  pkgs.testers.runNixOSTest {
    name = "hyper-svid-test";
    nodes.machine = testModule;

    testScript = ''
      machine.wait_for_unit("multi-user.target")

      # Wait for the server to be listening
      machine.wait_for_unit("hyper-svid-server.service")
      machine.succeed("sleep 2") # Give it a moment to bind

      # Start the agent service via systemctl
      machine.succeed("systemctl start hyper-svid-agent.service")

      # Start the workload service and verify the Workload API dynamically issued credentials and rotation
      with subtest("-- workload api test --"):
          machine.wait_for_file("/run/hyper-svid/workload.sock")
          machine.succeed("systemctl start service-a.service")

          # Wait for the credentials to be written to /tmp by the workload
          machine.wait_for_file("/tmp/workload-cert-service-a.pem")

          # Verify IP SAN is embedded in the dynamically requested workload cert
          workload_cert_text = machine.succeed("openssl x509 -in /tmp/workload-cert-service-a.pem -noout -text")
          assert "IP Address:127.0.0.1" in workload_cert_text
          assert "CN=service-a" in workload_cert_text

          # Wait for rotation test file confirming successful rotation at half-lifetime
          machine.wait_for_file("/tmp/rotation-passed")
          print("\033[94m" + "\n-- workload api test completed successfully (rotation verified) --\n" + "\033[0m")

      # Verify service-b and service-c using UNIX-only selectors
      print("\n\n")
      with subtest("-- service b and c verification --"):
          machine.succeed("sudo -u service-b env USER=service-b workload-test-workload /run/hyper-svid/workload.sock")
          cert_b = machine.succeed("openssl x509 -in /tmp/workload-cert-service-b.pem -noout -text")
          assert "CN=service-b" in cert_b

          machine.succeed("sudo -u service-c env USER=service-c workload-test-workload /run/hyper-svid/workload.sock")
          cert_c = machine.succeed("openssl x509 -in /tmp/workload-cert-service-c.pem -noout -text")
          assert "CN=service-c" in cert_c
          print("\033[94m" + "-- service b and c verification completed successfully --" + "\033[0m")

      # Evaluate service-a's identity using the evaluator test binary
      print("\n\n")
      with subtest("-- capability eval test(rust) --"):
          machine.succeed("check-svid-rust /tmp/workload-cert-service-a.pem /etc/hyper-svid/ca/ca-cert.pem")
          print("\033[94m" + "-- capability eval test(rust) completed successfully --" + "\033[0m")

      print("\n\n")
      with subtest("-- capability eval test(go) --"):
          machine.succeed("check-svid-go /tmp/workload-cert-service-a.pem /etc/hyper-svid/ca/ca-cert.pem")
          print("\033[94m" + "-- capability eval test(go) completed successfully --" + "\033[0m")

      # Test CLI flags for attestation reset
      print("\n\n")
      with subtest("-- test server CLI attestation reset --"):
          machine.succeed("hyper-svid-server --reset-attestation local-vm")
          print("\033[94m" + "-- attestation reset CLI verified successfully --" + "\033[0m")

      # Test server time sync notification signal and certificate rotation
      print("\n\n")
      with subtest("-- test server time sync notification & cert rotation --"):
          server_pid = machine.succeed("systemctl show --property=MainPID --value hyper-svid-server.service").strip()
          machine.succeed(f"kill -USR1 {server_pid}")
          machine.succeed("sleep 2")
          agent_log = machine.succeed("journalctl -u hyper-svid-agent.service")
          assert "TimeSyncNotification" in agent_log or "Proactively requesting rotated certificate" in agent_log
          print("\033[94m" + "-- time sync notification & rotation test completed successfully --" + "\033[0m")

      print("\n\n")
      with subtest("-- get status of hyper-svid server --"):
        status = machine.succeed("systemctl status hyper-svid-server.service")
        print(status)
        print("\033[94m" + "-- status of hyper-svid server retrieved successfully --" + "\033[0m")

      print("\n\n")
    '';
  }
