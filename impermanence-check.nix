{
  lib,

  btrfs-progs,
  coreutils,
  gawk,
  hostname,
  writeShellScriptBin,

  nixosConfigurations ? {},
  ...
}:

let
  inherit (lib)
  attrsToList
  concatMapAttrsStringSep
  concatMapStringsSep
  concatStringsSep
  filter
  filterAttrs
  flatten
  head
  length
  imap0
  pipe;

  loadRawSubvolumes = cfg: concatMapStringsSep "\n" (device: ''
    mapfile -t -O "''${#subvolsraw[@]}" subvolsraw < <( \
      ${btrfs-progs}/bin/btrfs subvolume list ${device.mntPoint} \
      | ${coreutils}/bin/cut -d" " -f9- \
      | ${gawk}/bin/awk '{print "${device.mntPoint}/"$1}' \
    )
  '') cfg.devices;

  filterSubvolumes = cfg: pipe cfg.devices [
    (map (device:
      (map (origin: "${device.mntPoint}/${origin.path}") device.origins)
    ))
    flatten
    (map (prefix: ''
      mapfile -t -O "''${#subvols[@]}" subvols < <( \
        ${coreutils}/bin/printf "%s\n" "''${subvolsraw[@]}" \
        | ${gawk}/bin/awk -v s="${prefix}" 'index($0, s) == 1' \
      )
    ''))
    (concatStringsSep "\n")
  ];

  getOriginPrefix = cfg: find-origin: pipe cfg.devices [
    (map (device: pipe device.origins [
      (filter (origin: origin.label == find-origin))
      (map (origin: "${device.mntPoint}/${origin.path}"))
    ]))
    flatten
    head
  ];

  loadMounts = cfg: pipe cfg.paths [
    (filter (path: !path.file))
    (imap0 (i: path: ''
      mounts[${toString i}]="${getOriginPrefix cfg path.origin}${path.path}"
    ''))
    (concatStringsSep "\n")
  ];

  impermanenceConfigured = nixcfg:
    nixcfg?config.environment.impermanence-subvolumes
    && nixcfg.config.environment.impermanence-subvolumes.enable;

  impermanenceConfiguredWithPaths = nixcfg:
    impermanenceConfigured nixcfg
    && length (nixcfg.config.environment.impermanence-subvolumes.paths) > 0;

  hostnameWarnings = pipe nixosConfigurations [
    attrsToList
    (imap0 (i: cfgAttr: ''
      ${if i > 0 then "el" else ""}if [[ "$hostname" == "${cfgAttr.value.config.networking.hostName}" ]]; then
    '' + (if impermanenceConfigured cfgAttr.value then ''
      echo "checking impermanence configuration for ${cfgAttr.name} (hostname: $hostname)"
    '' else ''
      echo "impermanence not configured for ${cfgAttr.name} (hostname: $hostname)"
      exit 1
    '' )))
    (concatStringsSep "\n")
    (x: x + ''
      else
        echo "hostname not recognized: $hostname"
        exit 1
      fi
    '')
  ];

  mkIfHostname = gen: concatMapAttrsStringSep "\n" (nixcfgName: nixcfg: 
    if impermanenceConfiguredWithPaths nixcfg then ''
      if [[ "$hostname" == "${nixcfg.config.networking.hostName}" ]]; then
        ${gen nixcfg.config.environment.impermanence-subvolumes}
      fi
    '' else ""
  ) nixosConfigurations;
in writeShellScriptBin "impermanence-check" ''
  hostname=$(${hostname}/bin/hostname)
  ${hostnameWarnings}
  declare -a subvolsraw
  ${mkIfHostname loadRawSubvolumes}
  declare -a subvols
  ${mkIfHostname filterSubvolumes}   # remove subvols not starting with mntPoint + origin path
  declare -a mounts
  ${mkIfHostname loadMounts}

  echo no matching subvol:
  ${coreutils}/bin/comm -13 \
    <(${coreutils}/bin/printf '%s\n' "''${subvols[@]}" | ${coreutils}/bin/sort) \
    <(${coreutils}/bin/printf '%s\n' "''${mounts[@]}" | ${coreutils}/bin/sort)

  echo
  echo unused btrfs subvols:
  ${coreutils}/bin/comm -23 \
    <(${coreutils}/bin/printf '%s\n' "''${subvols[@]}" | ${coreutils}/bin/sort) \
    <(${coreutils}/bin/printf '%s\n' "''${mounts[@]}" | ${coreutils}/bin/sort)
''
