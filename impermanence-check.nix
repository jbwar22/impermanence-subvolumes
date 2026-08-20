{
  lib,

  btrfs-progs,
  coreutils,
  gawk,
  writeShellScriptBin,

  config ? {},
  ...
}:

let
  script-body = if
    config?environment.impermanence-subvolumes
    && config.environment.impermanence-subvolumes.enable
  then
    (let
      inherit (lib)
      concatMapStringsSep
      concatStringsSep
      filter
      flatten
      head
      imap0
      pipe;

      cfg = config.environment.impermanence-subvolumes;

      loadRawSubvolumes = concatMapStringsSep "\n" (device: ''
        mapfile -t -O "''${#subvolsraw[@]}" subvolsraw < <( \
          ${btrfs-progs}/bin/btrfs subvolume list ${device.mntPoint} \
          | ${coreutils}/bin/cut -d" " -f9- \
          | ${gawk}/bin/awk '{print "${device.mntPoint}/"$1}' \
        )
      '') cfg.devices;

      filterSubvolumes = pipe cfg.devices [
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

      getOriginPrefix = find-origin: pipe cfg.devices [
        (map (device: pipe device.origins [
          (filter (origin: origin.label == find-origin))
          (map (origin: "${device.mntPoint}/${origin.path}"))
        ]))
        flatten
        head
      ];

      loadMounts = pipe cfg.paths [
        (filter (path: !path.file))
        (imap0 (i: path: ''
          mounts[${toString i}]="${getOriginPrefix path.origin}${path.path}"
        ''))
        (concatStringsSep "\n")
      ];
    in ''
      declare -a subvolsraw
      ${loadRawSubvolumes}
      declare -a subvols
      ${filterSubvolumes}   # remove subvols not starting with mntPoint + origin path
      declare -a mounts
      ${loadMounts}

      echo no matching subvol:
      ${coreutils}/bin/comm -13 \
        <(${coreutils}/bin/printf '%s\n' "''${subvols[@]}" | ${coreutils}/bin/sort) \
        <(${coreutils}/bin/printf '%s\n' "''${mounts[@]}" | ${coreutils}/bin/sort)

      echo
      echo unused btrfs subvols:
      ${coreutils}/bin/comm -23 \
        <(${coreutils}/bin/printf '%s\n' "''${subvols[@]}" | ${coreutils}/bin/sort) \
        <(${coreutils}/bin/printf '%s\n' "''${mounts[@]}" | ${coreutils}/bin/sort)
    '')
  else
    ''
      echo impermanence-subvolumes not configured!
    '';
in writeShellScriptBin "impermanence-check" script-body

