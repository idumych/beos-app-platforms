# Audio apps: Media Kit nodes, system-wide effects, audio tests

For apps that process or route sound (effects, equalizers, players with DSP), and for
porting Linux audio apps built on PipeWire/PulseAudio. Worked example: JamesDSP for
Linux (Audio4Linux/JDSP4Linux), Oct 2026: its libjamesdsp engine as a filter node
between the system mixer and the sound card (branch `haiku-media-node`, `haiku/`).

## What maps and what doesn't

| Linux (PipeWire/Pulse) | Haiku / Renku Media Kit |
|---|---|
| Filter on all system audio | A filter node inserted between the **system mixer** and the **audio output** with `BMediaRoster` (no graph manager does it for you) |
| Per-app streams, per-app routing/blocklists | Each app is a producer connected to the mixer; per-app control means rewiring each app's connection. Leave out at first |
| Per-device presets, device switching | One default output; changing it in Media preferences restarts the media services, and the node must be inserted again |
| D-Bus control, tray icon | BMessages to the node's control port (`write_port`), `hey`, a Deskbar replicant |

Do the risky part first: a headless node plus a command-line inserter, tested end to end in
a VM, before writing any UI. If the audio path fails, the port isn't viable.

## Structure

- **Portable engine** (`core/`, no Haiku headers): wrap the DSP library behind
  `SetSampleRate`, `ApplyConfig(map)`, `Process(interleaved buffer, frames)` for float, int16
  and int32. Reuse the Linux app's settings file format so presets carry over. Give it a host
  test that runs sines through it in mixer-sized buffers and checks each effect's gain.
- **Media add-on** (`B_FLAVOR_IS_GLOBAL`, `possible_count = 1`): one flavor,
  `B_BUFFER_CONSUMER | B_BUFFER_PRODUCER`, raw audio wildcard in and out. Global means the
  node lives in `media_addon_server` and outlives the tool that inserted it. Haiku's
  Equalizer add-on (`src/add-ons/media/media-add-ons/equalizer`, MIT) is the shape to copy:
  `BBufferConsumer + BBufferProducer + BMediaEventLooper`, buffers processed in place in
  `BufferReceived` and passed on with `SendBuffer`, `SetBufferGroup` forwarded upstream with
  `SetOutputBuffersFor` so the mixer writes into the output's buffers.
- **Inserter tool** (`jdspctl insert|remove|status|reload`, needs a `BApplication`):
  `GetAudioMixer`, `GetAudioOutput`, find the mixer→output link (`GetConnectedOutputsFor`
  / `GetConnectedInputsFor`, match source and destination), `Disconnect`, `Connect`
  mixer→node and node→output **with the existing link's exact format**, and reconnect
  mixer→output if anything fails. `GetDormantNodes(…, name)` + `InstantiateDormantNode(…,
  B_FLAVOR_IS_GLOBAL)`; `GetLiveNodes(…, name)` finds it again later. Settings reload: a
  custom message code written to the node's `ControlPort()`, handled first in
  `HandleMessage`.

## Traps

- **The system mixer auto-starts only the node it feeds.** It runs in auto-stop mode
  (`AudioMixer::_AutoStart/_AutoStop`): when the first app connects it calls `StartNode`
  on its downstream node, and stops it when the last app leaves. With a filter in between,
  that's the filter, so the audio output never starts. Every node uses the output's clock
  as its time source, and the mixer waits for that clock before mixing (`MixerCore::_MixThread`
  loops until the time source has published within the last second), so the result is
  silence: no buffers, no error. Fix: override `Start()`/`Stop()` in the filter, call the
  base class, then `StartNode`/`StopNode` the downstream node (`NodeIDFor(output
  destination port)` → `GetNodeFor`, `GetStartLatencyFor`). Don't `StartNode` the filter
  from the inserter; the mixer does it when apps play.
- **Diagnosing silence:** print each node's time source with `MakeTimeSourceFor(node)` →
  `GetTime()`: performance 0 and "published N seconds ago" means the output's clock isn't
  running. `KERN: hda_stream_start()` in the syslog marks the sound card actually starting.
  Count received/dropped/send-failed buffers in the node and log them every few seconds.
- **Format:** take it from the existing mixer→output link; don't assume float. On QEMU's
  HDA it was 96 kHz, 2 ch, **int16**, 24576-byte (64 ms) buffers. Support float, int16 and
  int32, keep the same format on both sides, reject non-stereo.
- **New add-on files are picked up without a restart**: `cp` into
  `$(finddir B_USER_NONPACKAGED_ADDONS_DIRECTORY)/media/` and `InstantiateDormantNode` finds
  it. **Replacing** one that's loaded needs the media services restarted:
  `launch_roster stop x-vnd.haiku-media_server; launch_roster start x-vnd.haiku-media_server`
  (worked at runtime on Renku build00064).
- **Latency:** report processing time in `GetLatencyFor` and send `SendLatencyChange`
  upstream after connecting. Time a few silent buffers of the negotiated size and add
  headroom (JamesDSP: ~5–7 ms on top of the mixer's ~130 ms).
- `ReleaseNode` on a global node doesn't delete it; it stays live (harmless, `GetLiveNodes`
  finds it for the next insert).
- Renku's multi_audio node stops its output thread when every HDA stream is parked; it
  restarts only on `Start`. Another reason the start must reach it.

## Testing audio end to end

1. Run the guest in QEMU with `scripts/qemu-vm.sh` (`AUDIO=wav`): every sample the guest's
   sound card plays lands in `$DIR/audio.wav`, with no host audio involved.
2. Build `scripts/tone.cpp` in the guest. For each case: write the settings, reload the
   node, note the WAV size, `ssh guest ./tone FREQ L R SECONDS`, wait ~2 s, note the size,
   and run `scripts/sine-check.py WAV FREQ START END`.
3. Compare levels with the same tone played **with the node removed**: post gain −6 dB
   should give 0.501, an EQ cut its dB value, crossfeed a left-only tone some right
   channel. These should match the portable engine's host test exactly.
4. Dropouts should be 0. Don't count clicks as residuals from an ideal sine: QEMU's rate
   conversion leaves single-sample kinks on its chunk boundaries with or without your node
   (sine-check.py's docstring). A real dropout shows as a phase jump or silence. Real
   dropouts (forward jumps of ~10–15 samples with an amplitude dip) also appear when the
   host is busy (load average ~4.5 on a 4-core host), so judge the node only against
   tone runs without it, alternated in the same minutes, never against an earlier
   baseline. If dropouts show up with the node and not without it, the node's own
   counters (late notices, worst processing time) say whether it's the cause.
5. Also read the node's own counters: dropped buffers, send errors, late notices, and
   worst processing time against the buffer duration.

Say in reports that this was QEMU's emulated HDA; real hardware is still the final check.
