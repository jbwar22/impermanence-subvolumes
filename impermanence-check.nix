{
  lib,

  btrfs-progs,
  coreutils,
  findutils,
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
  flatten
  head
  imap0
  length
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
      mapfile -t -O "''${#realpaths[@]}" realpaths < <( \
        ${coreutils}/bin/printf "%s\n" "''${subvolsraw[@]}" \
        | ${gawk}/bin/awk -v s="${prefix}" 'index($0, s) == 1' \
      )
    ''))
    (concatStringsSep "\n")
  ];

  loadFiles = cfg: concatMapStringsSep "\n" (device:
    (concatMapStringsSep "\n" (origin: ''
      mapfile -t -O "''${#realpaths[@]}" realpaths < <( \
        ${findutils}/bin/find ${device.mntPoint}/${origin.path} -xdev -type f \
      )
    '') device.origins)
  ) cfg.devices;

  getOriginPrefix = cfg: find-origin: pipe cfg.devices [
    (map (device: pipe device.origins [
      (filter (origin: origin.label == find-origin))
      (map (origin: "${device.mntPoint}/${origin.path}"))
    ]))
    flatten
    head
  ];

  loadCfgPaths = cfg: pipe cfg.paths [
    (imap0 (i: path: ''
      cfgpaths[${toString i}]="${getOriginPrefix cfg path.origin}${path.path}"
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
  declare -a realpaths
  ${mkIfHostname filterSubvolumes}
  ${mkIfHostname loadFiles}
  declare -a cfgpaths
  ${mkIfHostname loadCfgPaths}

  echo missing real path:
  ${coreutils}/bin/comm -13 \
    <(${coreutils}/bin/printf '%s\n' "''${realpaths[@]}" | ${coreutils}/bin/sort) \
    <(${coreutils}/bin/printf '%s\n' "''${cfgpaths[@]}" | ${coreutils}/bin/sort)

  echo
  echo real path not in cfg:
  ${coreutils}/bin/comm -23 \
    <(${coreutils}/bin/printf '%s\n' "''${realpaths[@]}" | ${coreutils}/bin/sort) \
    <(${coreutils}/bin/printf '%s\n' "''${cfgpaths[@]}" | ${coreutils}/bin/sort)
''
