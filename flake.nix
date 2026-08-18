{
  description = "impermanence on btrfs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { nixpkgs, ... }: {
    nixosModules = rec {
      impermanence-subvolumes = import ./nixos.nix;
      default = impermanence-subvolumes;
    };
    homeManagerModules = rec {
      impermanence-subvolumes = import ./home.nix;
      default = impermanence-subvolumes;
    };
    packages."x86_64-linux" = let
      pkgs = nixpkgs.legacyPackages."x86_64-linux";
    in rec {
      default = impermanence-check;
      impermanence-check = pkgs.callPackage ./impermanence-check.nix {};
    };
  };
}
