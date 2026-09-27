{
  pkgs,
  hyperSvid,
}: let
  testModule = {lib, ...}: {
    environment.systemPackages = [hyperSvid];
  };
in
  pkgs.testers.runNixOSTest {
    name = "hyper-svid-profiler-test";
    nodes.machine = testModule;

    testScript = ''
      machine.wait_for_unit("multi-user.target")

      output = machine.succeed("profiler")
      print("\n=== PROFILER OUTPUT ===")
      print(output)
      print("=======================\n")
    '';
  }
