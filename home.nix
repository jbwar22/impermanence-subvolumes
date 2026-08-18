{ lib, ... }:

with lib; {
  options.environment.impermanence-subvolumes = {
    enable = mkEnableOption "home impermanence-subvolumes";
    paths = mkOption {
      type = with types; listOf (coercedTo str (x:
        if typeOf x == "string" then {
          path = x;
        } else x
      ) (submodule {
        options = {
          path = mkOption {
            type = str;
            description = "path";
          };
          file = mkEnableOption "is the path a file rather than a dir";
          origin = mkOption {
            type = nullOr str;
            description = "origin of path";
            default = null;
          };
          neededForBoot = mkEnableOption "needed in early stages";
        };
      }));
      description = "extra paths to persist";
      default = [];
    };
  };
}
