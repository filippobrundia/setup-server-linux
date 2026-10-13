# Profilo SOLO per l'adattatore root-owned di Claude, non per /usr/bin/bwrap.
# Attachment diretto: non usare aa-exec, ristretto da Ubuntu 26.04.
abi <abi/4.0>,
include <tunables/global>
profile ops-claude-sandbox /usr/local/libexec/ops-claude-sandbox/bwrap flags=(attach_disconnected,mediate_deleted) {
  file,
  capability,
  network,
  unix,
  userns,
  mount,
  umount,
  pivot_root,
  signal,
  ptrace,
  /usr/bin/bwrap ix,
  /** ix,
}
