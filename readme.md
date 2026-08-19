# impermanence-subvolumes
My highly opinionated implementation of impermanence, using btrfs.

## Implementation
- For use with a tmpfs root (not configured in this module)
- Btrfs subvolume for each mountpoint
- Bind mount for individual files
  - workaround for where this is absolutely necessary, not for high I/O utilized files
- Multiple "origins" for subvolumes to live in
  - Allows isolation of different types of data
  - For example, complete separation of persistant data you wish to back up, vs data you don't care about backing up, and/or control over what device persistant data lives in
- Check script to ensure volumes are all present

## Rationale
Bind mounted directories were causing high CPU overhead during intense I/O, so I moved to using pure btrfs subvolume mounts.


## Usage
in flake inputs:
```
impermanence-subvolumes = {
    url = "github:jbwar22/impermanence-subvolumes";
    inputs.nixpkgs.follows = "nixpkgs-stable";
};
```
### NixOS Module
add the NixOS module:
```
inputs.impermanence-subvolumes.nixosModules.impermanence-subvolumes
```
and configure:
```
environment.impermanence-subvolumes = {
  enable = true;
  defaultOrigin = "back"; # default origin for paths defined with just a string
  devices = [
    {
      device = "/dev/disk/..."; # device file
      subvol = "/"; # subvol where origins are located directly under
      mntPoint = "/persist"; # where to mount the device
      mntOptions = [ ... ]; # options to mount with
      origins = [
        {
          path = "back/root"; # where the root folder is for this origin on the device
          label = "back"; # for identifying (defaultOrigin and paths)
        }
        {
          path = "local/root";
          label = "local";
        }
        ...
      ]
    }
    ...
  ];
  paths = [
    "/var/lib/nixos" # simple path on default origin
    { path = "/etc/ssh"; neededForBoot = true; } # mark as needed for boot
    { path = "/var/log"; origin = "local"; } # mark from a different origin
    { path = "/etc/localtime"; file = true; } # individual file mount
  ];
}
```
this would require the following disk layout:
```
/dev/disk/...                   # device option (btrfs partition)
└── subvol: /                   # subvol option (btrfs subvol)
    ├── back                    # dir (origin)
    │   └── root                # dir (origin path)
    │       ├── var             # dir
    │       │   └── lib         # dir
    │       │       └── nixos   # btrfs subvol (path, dir)
    │       └── etc             # dir
    │           ├── ssh         # btrfs subvol (path, dir)
    │           └── localtime   # file (path, file)
    └── local                   # dir (origin)
        └── root                # dir (origin path)
            └── var             # dir
                └── log         # btrfs subvol (path, dir)
```

### home-manager module
optionally add the home-manager module for user-defined mounts.
Only compatible with home-manager as a NixOS module, and only does anything if you have the NixOS module installed too.
```
inputs.impermanence-subvolumes.homeManagerModules.impermanence-subvolumes
```
Then you can just define `environment.impermanence.subvolumes.paths`, with paths relative to your home folder.
The NixOS module will automatically detect configured users' paths and include them in the system impermanence paths list

## Check script
Override the impermanence-check package output with your nixosConfigurations to build the impermanence check script
```
inputs.impermanence-subvolumes.packages."x86_64-linux".impermanence-check.override { nixosConfigurations = self.nixosConfigurations; }
```
then you can run:
```
impermanence-check HOSTNAME
```
to check current mounted volumes against the HOSTNAME nixosConfiguration
