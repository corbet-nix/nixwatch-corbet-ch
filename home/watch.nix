# The cksk watch feed on the home-manager plane: put the cksk binary on PATH, render its
# per-host config.json, and run it as an ORDINARY graphical-session service.
#
# cksk itself lives in its own product repo (corbet-labs/cksk) -- this module is only the
# thin nix-side wiring that deploys it onto a seat. It builds nothing: `package` is
# supplied from outside (in production an AUR cksk-bin wrapper, same shape as the
# nixlock-bin wrapper -- see the host's own nixlock.nix AUR intent).
#
# NOT THE LOCK COMMAND. clck (nixlock today) is the locker (its own home-manager module
# owns the session idle/lock command); cksk is a plain socket CLIENT that streams its
# boards onto the locker's kiosk display socket (see the display server's README
# "Streaming kiosk content" / BEHAVIORS.md DISPLAY-1/DISPLAY-2) and has no lock/idle role
# of its own at all. It needs no `kioskOutputs` and no `pamService` either -- the kiosk
# output's geometry comes from the server's own HELLO handshake at connect time, and
# unlock stays entirely the locker's PAM concern.
#
# GRAPHICAL-SESSION SERVICE. Ordered after `graphical-session.target` (so it inherits
# WAYLAND_DISPLAY/XDG_RUNTIME_DIR the compositor's own launch exports into the systemd
# --user manager's GLOBAL environment) and restarted on failure -- the display server is
# not always up first (e.g. right after a compositor restart, or if it is mid-restart),
# and cksk's own connect loop already retries with backoff, so a `Restart=on-failure`
# here only covers cksk crashing outright, not the ordinary "server isn't listening yet"
# case (that path never exits at all -- see the binary's own header).
#
# MECHANISM PUBLIC, VALUES PRIVATE. This module is the mechanism: it knows HOW to render the
# config and HOW to wire the service. The real value -- which statuses API this host watches --
# is a host's own business and lives in the private infra tree, not here. Everything in this file
# is either a neutral default or an example (`https://status.example.com/...`); nothing names a
# real host or URL.
#
# Filename note (docs/module-layout.md in infra): this file fills `nixwatch.kiosk` and is
# named for the cksk watch feed it deploys, mirroring how a host's own `nixlock.nix` is
# named for the flake it consumes. The option namespace is unchanged.
{ lib, config, ... }:
let
  cfg = config.nixwatch.kiosk;
in
{
  options.nixwatch.kiosk = {
    enable = lib.mkEnableOption "cksk watch feed for a kiosk display socket";

    package = lib.mkOption {
      type = lib.types.package;
      description = ''
        The cksk package to run. Supplied from outside this repo -- cksk is built
        and released from its own product repository (corbet-labs/cksk), never here.
      '';
    };

    gatusUrl = lib.mkOption {
      type = lib.types.str;
      description = ''
        The statuses observability API URL this kiosk polls for endpoint statuses
        (its `/api/v1/endpoints/statuses` JSON). A fact about this host's
        observability stack, not a default this module should invent -- there
        is no built-in fallback here (the binary itself falls back to a
        neutral placeholder if this is ever left unset upstream of it).
      '';
    };

    socketPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/user/1000/clck.sock";
      description = ''
        Path to the display server's kiosk display Unix socket. `null` (the default)
        leaves it to the binary's own default, `$XDG_RUNTIME_DIR/clck.sock` (falling
        back to the previous nixlock name) -- correct as long as both run in the same
        session (the normal case: both are per-session graphical services sharing one
        `$XDG_RUNTIME_DIR`). Only set this to point at a different session's socket.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The binary on PATH, for interactive use / a keybind that restarts it.
    home.packages = [ cfg.package ];

    # The value channel this service's own ExecStart cannot carry inline. Keys match the binary's
    # own FileConfig: gatus_url, socket_path.
    xdg.configFile."cksk/config.json".text = builtins.toJSON (
      { gatus_url = cfg.gatusUrl; }
      // lib.optionalAttrs (cfg.socketPath != null) { socket_path = cfg.socketPath; }
    );

    systemd.user.services.cksk-watch = {
      Unit = {
        Description = "cksk watch feed -- streams status boards to a kiosk display socket";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${cfg.package}/bin/cksk";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
