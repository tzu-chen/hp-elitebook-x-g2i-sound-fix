#!/usr/bin/env bash
# HP EliteBook X G2i stereo fix — run ONCE as root after the post-install
# reboot. Sets the speaker DSP gain stages to 0 dB and persists them.
#
# Background: the topology's "Pre/Post Mixer Speaker Playback Volume"
# kcontrols default to 0 = -90 dB. If a zeroed asound.state ever gets saved,
# udev's alsactl re-applies it on EVERY card creation — the classic
# "everything looks fine but total silence" trap. Setting 45 (= 0 dB) and
# storing makes the good values the persisted ones.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root: sudo bash $0"; exit 1; }

aplay -l | grep -q Speaker || { echo "no Speaker PCM — check dmesg for tas2783/SOF errors"; exit 1; }

amixer -c0 cset name='Pre Mixer Speaker Playback Volume' 45,45
amixer -c0 cset name='Post Mixer Speaker Playback Volume' 45,45
alsactl store

journalctl -k -b --no-pager | grep -E 'tas2783 4-amp|splitting into 2 PDIs|loading topology 0' || true
echo
echo "Expect above: 'reordered amps for 2-PDI stereo', 'splitting into 2 PDIs',"
echo "and 'loading topology 0: .../sof-sdca-2amp-id2.tplg'."
echo "Test stereo with any L/R-panned audio — low/left vs high/right should"
echo "come from the correct side of the laptop."
