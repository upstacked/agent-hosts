# One disk, bootable both ways: a BIOS boot partition for GRUB on machines
# without UEFI, and an ESP for those with it. Proxmox VMs come as either.
{ lib, host, ... }:
{
  disko.devices.disk.main = {
    type = "disk";
    device = host.disk or "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          size = "1M";
          type = "EF02";
        };
        esp = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
