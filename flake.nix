{
  description = "Development shell for Linux power measurements";

  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      eachSystem = f: builtins.listToAttrs (map (system: {
        name = system;
        value = f system;
      }) systems);
    in
    {
      devShells = eachSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.powerstat
              pkgs.powertop
              pkgs.upower
              pkgs.lm_sensors
              pkgs.pciutils
              pkgs.usbutils
            ] ++ pkgs.lib.optionals (system == "x86_64-linux") [
              pkgs.linuxPackages.turbostat
              pkgs.perf
              pkgs.intel-gpu-tools
            ];
          };
        });
    };
}
