# HP EliteBook X G2i — 4-speaker TRUE STEREO fix (Fedora 44, sof-soundwire)

DMI: `HP EliteBook X G2i 14 inch Notebook Next Gen AI PC`, board `8E86`, HP.
Panther Lake, SOF IPC4. Built/tested on kernel **7.0.11-200.fc44.x86_64**.
**Status: working & daily-stable** — all four speakers, correct left/right
imaging, through normal PipeWire, surviving suspend/resume.

## Hardware
| SoundWire link | Device(s) | Role |
|---|---|---|
| Link 3 | Realtek **RT712** (SDCA: jack + mic) | headset jack + internal mic |
| Link 2 | 4× TI **TAS2783** mono SmartAmp | speakers: uid `0x9`=R woofer, `0xa`=R tweeter, `0xc`=L woofer, `0xd`=L tweeter |

## What was broken
1. **No speakers at all**: the amp driver requests firmware `8E86-2-9.bin` etc.
   but linux-firmware ships `8E86-2-0x9.bin.xz` (name mismatch → ENOENT), and
   HP's ACPI omits the SDCA DisCo amp endpoint so the kernel dropped all four
   amps (`cfg-amp:0`, no Speaker PCM).
2. **Mono-left only** (after fixing 1): all four amps read SoundWire slot 0.
   Each TAS2783 is a mono amp; the bus packs stream slots by codec list order,
   and with one 2ch PDI only the broadcast mask reaches all four — every amp
   plays the left channel.

## How stereo works (the 2-PDI design)
* `hda.c` reorders the amp list to `[0xc, 0x9, 0xd, 0xa]` = [L,R,L,R] by
  physical side.
* `sof_sdw.c` splits the 4-amp dai_link across **two CPU DAI pins → two 2ch
  PDIs** on the one link. With 2 CPU pins the shipped
  `sof-sdca-2amp-id2.tplg` topology auto-loads (no custom topology needed);
  its multi-gateway ALH copier duplicates the stereo stream to both PDIs.
* SoundWire slot packing then yields slots `[L,R,L,R]` — each amp's slot is
  its physical side. The TAS2783 driver gives each amp a 1-channel mask
  (`0x1` left amps / `0x2` right amps; DP1 ChannelEn only implements 2 bits).
* This exposed a real kernel bug: `sdw_stream_add_master()` let a second DAI
  on the same bus+stream **overwrite** the first port's config (ChannelEn=0
  everywhere, silent stream). `patches/01` fixes it to append ports instead.

The four patches in `patches/` carry everything (incl. the original endpoint
fix and a TAS2783 resume-timeout bump 5000→15000 ms); prebuilt modules for
7.0.11-200.fc44 are in `kmod/`.

## Install on an identical machine
```bash
sudo bash install.sh        # firmware aliases + 4 modules + resume service
sudo reboot
sudo bash post-reboot.sh    # speaker DSP gains to 0 dB + alsactl store
```
If the running kernel differs from the prebuilt modules, `install.sh` refuses;
run `bash build-modules.sh` first (needs kernel-devel, gcc, rpmbuild, dwarves —
downloads the Fedora kernel SRPM, applies `patches/`, builds into `kmod/`).

**After every kernel update**: `bash build-modules.sh && sudo bash install.sh`
and reboot — otherwise audio reverts to broken stock.

PipeWire: use the **pro-audio** profile; the speaker sink is `pro-output-2`.
(The HiFi UCM profile predates the amps and only shows Headphones/HDMI.)

## Suspend/resume
The TAS2783 driver's system-resume path leaves the amps powered but silent
(its runtime-resume is fine — TI driver bug, upstream-reportable).
`elitebook-audio-resume.service` (installed by `install.sh`) reloads the SOF
stack after every resume and restores the speaker gains. Expect ~10 s of
audio teardown/bring-up after each wake; log: `/var/log/elitebook-audio-resume.log`.

## Field guide (hard-won — read before debugging)
* **"Everything green but TOTAL silence"** → check
  `amixer -c0 cget name='Pre Mixer Speaker Playback Volume'` (and `Post`).
  They default to 0 = **-90 dB** and udev's alsactl re-applies a zeroed
  `asound.state` on every card re-create. Fix: both to 45, `alsactl store`.
  This masqueraded as three different "hardware wedges" during development.
* **Dead speaker after unplugging headphones** → stuck PipeWire sink mute on
  `pro-output-2` (pro-audio = no jack auto-routing), not hardware.
* **Don't reload the SOF stack repeatedly** (`elitebook-sof-reload`): after
  ~2 reloads in one boot the HDA controller can wedge
  (`failed to reset HDA controller gctl 0x1`) and only a reboot clears it.
* **Secure Boot**: modules are unsigned; this machine runs with Secure Boot
  off. Enable it and you must sign all four `.ko` files.
* Rollback: every replaced module is kept as `<name>.ko.xz.orig` next to the
  installed `.ko`; restore them, `depmod -a`, reboot.

## Files
| File | Purpose |
|---|---|
| `install.sh` | one-shot installer (firmware + modules + service) |
| `post-reboot.sh` | one-time gain init + alsactl store + sanity check |
| `build-modules.sh` | rebuild the 4 patched modules for a new kernel |
| `patches/01-…stream…` | soundwire: append (not overwrite) 2nd DAI's ports |
| `patches/02-…hda…` | SOF: force TAS2783 amp endpoint + reorder amps [c,9,d,a] |
| `patches/03-…sof-sdw…` | machine driver: split 4-amp link into 2 PDIs |
| `patches/04-…tas2783…` | amp driver: per-amp 1ch masks, set_tdm_slot, 15 s resume timeout |
| `kmod/*.ko` | prebuilt modules for 7.0.11-200.fc44.x86_64 |
| `system/*` | resume service unit + scripts (→ /usr/local/sbin, /etc/systemd/system) |

Full development history, dead ends, and debugging methodology:
`STEREO-PLAN.md` in this folder (untracked, this machine only).
