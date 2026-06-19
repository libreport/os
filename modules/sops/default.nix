{ ... }:
{
  sops = {
    defaultSopsFormat = "yaml";
    # Derive the age key from the host's SSH host key.
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    # defaultSopsFile is intentionally NOT set here — the consumer must set it
    # (each host points at its own secrets.yaml).
  };
}
