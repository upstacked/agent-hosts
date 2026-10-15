# upagent-reboot
#
# Reboots this machine if the running system's kernel, initrd, kernel modules
# or systemd are not the ones it booted. The reboot timer runs it.

booted=/run/booted-system
current=/run/current-system

for part in kernel initrd kernel-modules systemd; do
  if [ "$(readlink -f "$booted/$part")" != "$(readlink -f "$current/$part")" ]; then
    echo "upagent-reboot: $part changed since boot, rebooting"
    exec systemctl reboot
  fi
done

echo "upagent-reboot: running what it booted, nothing to do"
