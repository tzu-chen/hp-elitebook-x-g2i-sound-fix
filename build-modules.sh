#!/usr/bin/env bash
# Build the four patched kernel modules for the running (or given) Fedora
# kernel into kmod/. Re-run after every kernel update, then sudo install.sh.
# Run as your normal user (uses dnf only to download the kernel SRPM).
#
# Requires: kernel-devel matching the target kernel, gcc, make, rpmbuild,
# dwarves (pahole).
set -euo pipefail
KREL=${1:-$(uname -r)}                      # e.g. 7.0.11-200.fc44.x86_64
KVER=${KREL%.*}                             # strip arch -> 7.0.11-200.fc44
REPO="$(dirname "$(readlink -f "$0")")"
WORK=/var/tmp/elitebook-kmod

echo "==> Target kernel: $KREL"
command -v pahole >/dev/null || { echo "install dwarves: sudo dnf install -y dwarves"; exit 1; }
[[ -d /usr/src/kernels/$KREL ]] || { echo "install kernel-devel-$KREL"; exit 1; }

mkdir -p "$WORK"; cd "$WORK"
echo "==> Fetching kernel source RPM (if needed)"
ls kernel-${KVER%%-*}*.src.rpm >/dev/null 2>&1 || \
  dnf download --source kernel --enablerepo='*source*' || \
  { echo "could not download kernel SRPM"; exit 1; }

echo "==> Preparing source tree"
rpm -i kernel-${KVER%%-*}*.src.rpm 2>/dev/null || true
rpmbuild -bp --nodeps --target=x86_64 ~/rpmbuild/SPECS/kernel.spec 2>/dev/null || true
TREE=$(find ~/rpmbuild/BUILD -maxdepth 4 -type d -name "linux-${KVER}.*" 2>/dev/null | head -1)
[[ -n "$TREE" ]] || { echo "prepared tree not found under ~/rpmbuild/BUILD"; exit 1; }
echo "    tree: $TREE"

cd "$TREE"
cp -f /usr/src/kernels/$KREL/.config .config
cp -f /usr/src/kernels/$KREL/Module.symvers .
# struct module must include BTF fields to match the running kernel
./scripts/config --enable CONFIG_DEBUG_INFO_BTF --enable CONFIG_DEBUG_INFO_BTF_MODULES
make olddefconfig >/dev/null
[[ "$(make -s kernelrelease)" == "$KREL" ]] || echo "WARN: kernelrelease $(make -s kernelrelease) != $KREL"
make -j"$(nproc)" modules_prepare >/dev/null

echo "==> Applying patches"
for p in "$REPO"/patches/*.patch; do
    echo "    $(basename "$p")"
    patch -p1 -N -r - < "$p" || echo "    (already applied — or FAILED: check rejects if the kernel changed)"
done

# "Skipping BTF generation ... vmlinux unavailable" warnings are harmless as
# long as CONFIG_DEBUG_INFO_BTF_MODULES is set above.
build_one() { # <subdir> <module name>
    echo "==> Building $2"
    make -j"$(nproc)" M="$1" modules >/dev/null
    [[ -f "$1/$2.ko" ]] || { echo "build failed: $1/$2.ko"; exit 1; }
    cp -f "$1/$2.ko" "$REPO/kmod/"
    modinfo "$REPO/kmod/$2.ko" | grep vermagic | sed 's/^/    /'
}
mkdir -p "$REPO/kmod"
build_one drivers/soundwire          soundwire-bus
build_one sound/soc/sof/intel        snd-sof-intel-hda-generic
build_one sound/soc/intel/boards     snd-soc-sof-sdw
build_one sound/soc/codecs           snd-soc-tas2783-sdw

echo "==> All four modules built into $REPO/kmod/. Now: sudo bash install.sh && reboot"
