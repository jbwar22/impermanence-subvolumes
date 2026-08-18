# impermanence-subvolumes
My highly opinionated implementation of impermanence, using btrfs.

## Implementation:
- For use with a tmpfs root (not configured in this module)
- Btrfs subvolume for each mountpoint
- Bind mount for individual files
  - workaround for where this is absolutely necessary, not for high I/O utilized files
- Multiple "origins" for subvolumes to live in
  - Allows isolation of different types of data
  - For example, complete separation of persistant data you wish to back up, vs data you don't care about backing up, and/or control over what device persistant data lives in
- Check script to ensure volumes are all present

## Rationale:
Bind mounted directories were causing high CPU overhead during intense I/O, so I moved to using pure btrfs subvolume mounts.


## Usage:
in flake inputs:
```
impermanence-subvolumes = {
    url = "github:jbwar22/impermanence-subvolumes";
    inputs.nixpkgs.follows = "nixpkgs-stable";
};
```
add the nixos module:
```
inputs.impermanence-subvolumes.nixosModules.impermanence-subvolumes
```
optionally add the home-manager module for user-defined mounts.
Only compatible with home-manager as a nixos module, and only does anything if you have the nixos module installed too.
```
inputs.impermanence-subvolumes.homeManagerModules.impermanence-subvolumes
```

## Check script
Add the check script to flake outputs:
```
packages."x86_64-linux".impermanence-check = inputs.impermanence-subvolumes.packages."x86_64-linux".impermanence-check.override { nixosConfigurations = self.nixosConfigurations; };
```
then just run:
```
nix run .#impermanence-check HOSTNAME
```
to check current mounted volumes against the HOSTNAME nixosConfiguration
