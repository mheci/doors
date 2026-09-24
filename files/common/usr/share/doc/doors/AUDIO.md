# Doors audio policy

Every Doors image uses PipeWire and WirePlumber with a 48 kHz, 256-frame
low-latency baseline. PipeWire's X11 bell is disabled. PulseAudio-compatible
clients, including Proton and Wine, receive matching request defaults without
forcing a single unsafe hardware period size.

WirePlumber keeps ALSA nodes unsuspended and the HDA driver disables codec
power saving. This covers NVIDIA HDMI/DisplayPort nodes without relying on an
unverified PCI-name or vendor-property match.

## Anechoic microphone source

Doors builds only the LADSPA target from `mheci/anechoic` commit
`061038dd98d45abef5fc22ae9c27b289b50b180c`. The source archive, matching GPL
license, and build record are installed under `/usr/share/doors/anechoic/`.
The PipeWire filter chain exposes a passive virtual source named **Anechoic
Noise Suppression**. Select that source in an application or the desktop sound
settings to opt in; the original microphone remains available.

Default suppressor controls are intentionally conservative: VAD threshold 55%,
VAD grace 200 ms, no VAD hysteresis, and a -40 dB comfort-noise floor. A user
may override the system PipeWire drop-in with a file in
`~/.config/pipewire/pipewire.conf.d/` when a recording workflow needs different
trade-offs.

Physical audio validation is required after each image release, especially for
NVIDIA HDMI/DisplayPort suspend/resume and a real microphone. See
`docs/TEST-PLAN.md` in the source repository.
