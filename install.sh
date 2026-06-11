#!/usr/bin/env bash
# HP EliteBook X G2i — install the complete 4-speaker stereo fix.
#
#   1. TAS2783 firmware name aliases (driver requests 8E86-2-9.bin etc.;
#      linux-firmware ships them as 8E86-2-0x9.bin.xz — decompress + rename)
#   2. Four patched kernel modules from kmod/ (built from patches/ for the
#      EXACT running kernel — vermagic is checked; run build-modules.sh first
#      if it doesn't match). Installed UNCOMPRESSED: the kernel's built-in xz
#      module decompressor only supports CRC32, default xz output fails.
#   3. elitebook-audio-resume service (TAS2783 system-resume leaves the amps
#      powered but silent; the service reloads the SOF stack after every
#      suspend and restores the speaker DSP gains)
#
# Run as root:  sudo bash install.sh   — then REBOOT, then post-reboot.sh.
# Revert: restore all .ko.xz.orig files, rm the .ko files, depmod -a,
#         rm /lib/firmware/8E86-2-{9,A,C,D}.bin, disable the service, reboot.
set -euo pipefail
KREL=$(uname -r)
REPO="$(dirname "$(readlink -f "$0")")"

[[ $EUID -eq 0 ]] || { echo "run as root: sudo bash $0"; exit 1; }

echo "==> 1/3 TAS2783 firmware aliases"
for u in 9 A C D; do
    src=/lib/firmware/ti/audio/tas2783/8E86-2-0x$u.bin.xz
    dst=/lib/firmware/8E86-2-$u.bin
    [[ -f "$src" ]] || { echo "missing $src (install/upgrade linux-firmware)"; exit 1; }
    if [[ ! -f "$dst" ]]; then
        xzcat "$src" > "$dst"
        chmod 0644 "$dst"
        echo "    $dst"
    fi
done

echo "==> 2/3 patched kernel modules (kernel $KREL)"
install_ko() { # <name> <subdir under /lib/modules/$KREL/kernel>
    local name="$1" dir="/lib/modules/$KREL/kernel/$2" ko="$REPO/kmod/$1.ko" vm
    [[ -f "$ko" ]] || { echo "missing $ko (run build-modules.sh)"; exit 1; }
    vm=$(modinfo "$ko" | awk '/^vermagic/{print $2}')
    [[ "$vm" == "$KREL" ]] || { echo "vermagic mismatch for $name ($vm != $KREL); run build-modules.sh"; exit 1; }
    if [[ -e "$dir/$name.ko.xz" && ! -e "$dir/$name.ko.xz.orig" ]]; then
        cp -a "$dir/$name.ko.xz" "$dir/$name.ko.xz.orig"
    fi
    rm -f "$dir/$name.ko.xz"
    install -m0644 "$ko" "$dir/$name.ko"
    echo "    $dir/$name.ko"
}
install_ko soundwire-bus             drivers/soundwire
install_ko snd-sof-intel-hda-generic sound/soc/sof/intel
install_ko snd-soc-sof-sdw          sound/soc/intel/boards
install_ko snd-soc-tas2783-sdw      sound/soc/codecs
depmod -a "$KREL"

echo "==> 3/3 resume-recovery service"
install -m0755 "$REPO/system/elitebook-sof-reload"        /usr/local/sbin/elitebook-sof-reload
install -m0755 "$REPO/system/elitebook-audio-resume-fix"  /usr/local/sbin/elitebook-audio-resume-fix
install -m0644 "$REPO/system/elitebook-audio-resume.service" /etc/systemd/system/elitebook-audio-resume.service
systemctl daemon-reload
systemctl enable elitebook-audio-resume.service

echo
echo "Done. REBOOT now, then run:  sudo bash $REPO/post-reboot.sh"
