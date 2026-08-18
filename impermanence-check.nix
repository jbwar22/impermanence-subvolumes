{
  lib,

  btrfs-progs,
  coreutils,
  gawk,
  writeShellScriptBin,

  nixosConfigurations ? {},
  ...
}:

let
  inherit (lib)
  any
  attrsToList
  concatLines
  filter
  flatten
  hasAttr
  hasPrefix
  head
  imap0
  length
  pipe
  removePrefix;

  subvolPrefixes = cfg: pipe cfg.config.environment.impermanence-subvolumes.devices [
    (map (device: map (origin: let
      subvolRoot = if device.subvol == "/" then "" else "${device.subvol}/";
    in "${subvolRoot}${origin.path}") device.origins))
    flatten
  ];
  getMounts = cfg: pipe cfg.config.fileSystems [
    attrsToList
    (filter (x: x.value.fsType == "btrfs"))
    (map (x: pipe x [
      (x: x.value.options)
      (filter (y: hasPrefix "subvol=" y))
      (x: if (length x) > 0 then head x else "")
      (removePrefix "subvol=")
    ]))
    (filter (x: any (y: hasPrefix y x) (subvolPrefixes cfg)))
    (imap0 (i: x: "mounts[${toString i}]=\"${x}\""))
    concatLines
  ];
  getSubvolAppends = cfg: pipe cfg [
    subvolPrefixes
    (map (x: ''
      mapfile -t subvolstmp < <(${coreutils}/bin/printf '%s\n' "''${subvolsraw[@]}" | ${gawk}/bin/awk -v s="${x}" 'index($0, s) == 1')
      subvols+=("''${subvolstmp[@]}")
    ''))
    concatLines
  ];
  impermanenceHosts = pipe nixosConfigurations [
    attrsToList
    (filter (x: hasAttr "environment" x.value.config))
    (filter (x: hasAttr "impermanence-subvolumes" x.value.config.environment))
    (filter (x: x.value.config.environment.impermanence-subvolumes.enable))
  ];
  hasHosts = (length impermanenceHosts) != 0;
  mounts = (pipe impermanenceHosts [
    (imap0 (i: x: ''
      ${if i == 0 then "" else "el"}if [[ "$1" == "${x.name}" ]]; then
        ${getMounts x.value}
        ${getSubvolAppends x.value}
    ''))
    concatLines
  ]) + ''
    ${if hasHosts then "else" else ""}
      echo enter a hostname for which impermanence is enabled
      exit 1
    ${if hasHosts then "fi" else ""}
  '';
in
writeShellScriptBin "impermanence-check" ''
  mapfile -t subvolsraw < <(${btrfs-progs}/bin/btrfs subvolume list /persist | ${coreutils}/bin/cut -d" " -f9-)
  subvols=()

  ${mounts}

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
