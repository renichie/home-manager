# AppArmor profile for bubblewrap on Ubuntu 24.04+
#
# Ubuntu 24.04 restricts unprivileged user namespaces via AppArmor
# (kernel.apparmor_restrict_unprivileged_userns=1).
# This profile grants bwrap permission to create user namespaces.
#
# Install once:
#   sudo cp ~/.config/home-manager/scripts/bwrap-apparmor.profile /etc/apparmor.d/bwrap
#   sudo apparmor_parser -r /etc/apparmor.d/bwrap

abi <abi/4.0>,
include <tunables/global>

profile bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,
  include if exists <local/bwrap>
}
