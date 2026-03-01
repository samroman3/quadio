# Quadio Architecture

## Core Clarification

QS is not a standalone container format. The app ingests a normal 2-channel stereo PCM stream, where the quadraphonic phase information is matrix-encoded inside that stereo signal. In practice:

- Input: stereo PCM from `AVAudioFile`, `AVPlayer`, `AVAssetReader`, or a live stereo stream
- Decode step: pass stereo samples into the Quark QS decoder
- Output: four discrete PCM channels

The correct mental model is "2-channel stereo in, 4-channel decoded buses out."

## Product Shape

The system should be split into two app roles:

- Host: decodes stereo QS input into four channels, assigns channels to devices, and transmits scheduled audio packets
- Client: advertises itself on the LAN, receives one assigned channel, buffers it, and plays it at a scheduled time

This can ship as one iOS app with a role selector at launch, or as two targets (`QuadioHost` and `QuadioClient`) sharing the same core modules.

## Module Layout

Recommended target and module split:

- `App/`
  - SwiftUI shell, role selection, routing
- `Features/Host/`
  - device discovery UI
  - channel-to-device mapping UI
  - playback controls
- `Features/Client/`
  - availability status
  - assigned channel state
  - playback diagnostics
- `Core/Audio/`
  - PCM ingestion
  - decode pipeline
  - render scheduling
- `Core/Networking/`
  - Bonjour discovery
  - UDP transport
  - clock sync
  - packet encoding/decoding
- `Core/Models/`
  - shared DTOs, packet headers, channel IDs
- `Bridge/QSDecoder/`
  - Objective-C++ wrapper around Quark C++
- `Vendor/qs/`
  - extracted Quark sources required for decoding

## Audio Pipeline

### 1. Ingest

The host consumes standard stereo PCM in a fixed render format:

- sample rate: `48_000 Hz`
- sample format: `Float32`
- channel count: `2`
- frame block size: `256` or `512`

Everything should be resampled into this format before decoding. Locking the engine to `48 kHz` matches the Quark recommendation for coefficient generation and simplifies transport.

### 2. Decode

The host runs each stereo block through the QS decoder and emits:

- front left
- front right
- rear left
- rear right

These should remain planar `Float32` buffers in memory to avoid repeated interleave/deinterleave work.

### 3. Route

Each decoded bus is mapped to either:

- local playback
- a discovered client device
- muted / unassigned

The host should treat each of the four channels as an independently routable mono stream.

### 4. Transmit

For network-assigned outputs, the host packetizes mono PCM frames and sends them over UDP with:

- sequence number
- stream ID
- channel ID
- host clock timestamp
- target play timestamp
- sample rate
- frame count

### 5. Buffer and Play

The client receives packets, places them into a jitter buffer, aligns them against the synchronized host clock, and schedules playback using `AVAudioEngine`.

## C++ to Swift Interop

## Goal

Use Quark's active multiband QS decoder from Swift without rewriting the DSP.

## Approach

Extract the minimum decoding subset from `quarkquad/qs` into `Vendor/qs/`, then expose it through an Objective-C++ bridge.

Keep the bridge narrow:

- Swift never touches C++ types directly
- Swift passes raw sample pointers or `AVAudioPCMBuffer`
- Objective-C++ performs conversion and invokes the decoder

## Bridge Surface

Recommended bridge API:

- `QSDecoderBridge.create(sampleRate: Int32) -> UnsafeMutableRawPointer`
- `QSDecoderBridge.destroy(_ handle: UnsafeMutableRawPointer)`
- `QSDecoderBridge.decode(handle:..., leftIn:..., rightIn:..., frameCount:..., frontLeftOut:..., frontRightOut:..., rearLeftOut:..., rearRightOut:...)`

This is simpler and safer than trying to expose complex C++ classes across Swift boundaries.

## Implementation Notes

- Use an Objective-C++ `.mm` file as the boundary layer.
- Keep all Quark includes inside `.mm` or private C++ headers.
- Convert Swift buffers to contiguous `Float` pointers before decode.
- Allocate decoder state once and reuse it for the session.
- Avoid per-buffer heap allocation inside the decode call.

## Why not call JUCE directly?

The Quark repo is still JUCE-oriented. Pulling JUCE wholesale into an iOS app for one DSP block adds unnecessary build and integration cost. The better path is to isolate the decoder and adapt only the pieces it truly depends on.

## Networking

## Discovery

Use Bonjour over `Network.framework`.

Client:

- starts `NWListener`
- advertises a service such as `"_quadio._udp"`
- includes metadata in TXT records:
  - device name
  - app version
  - supported sample rate
  - current status

Host:

- starts `NWBrowser`
- maintains a registry of visible clients
- resolves endpoints and opens UDP connections to selected devices

## Channel Assignment Model

Each client should accept at most one active mono channel at a time in the first version. This simplifies:

- UI
- buffering
- transport state
- failure handling

The mapping model is:

- one host stream
- four logical output channels
- each channel mapped to zero or one sink

## Transport

Use UDP via `NWConnection` or lower-level BSD sockets if tighter control is needed.

Packet payload for V1 should be uncompressed mono PCM:

- `Float32` or `Int16`

For early development, `Float32` is easier because it matches the decoder output. For production, `Int16` usually cuts bandwidth in half with acceptable quality for this use case.

At `48 kHz`, mono `Float32` bandwidth is roughly:

- `48,000 samples/sec * 4 bytes = 192 KB/sec` per client, excluding headers

That is manageable for a few clients on a normal LAN, but `Int16` is a safer default for real-world Wi-Fi.

## Suggested Packet Header

Use a fixed-size binary header before the audio payload:

- magic (`UInt32`)
- protocol version (`UInt8`)
- packet type (`UInt8`)
- channel ID (`UInt8`)
- flags (`UInt8`)
- stream ID (`UInt32`)
- sequence (`UInt32`)
- host time in nanoseconds (`UInt64`)
- play-at host time in nanoseconds (`UInt64`)
- sample rate (`UInt32`)
- frame count (`UInt16`)
- payload format (`UInt8`)
- reserved (`UInt8`)

Keep the payload as raw PCM bytes after the header.

## Synchronization

This is the critical system.

## Do not rely on arrival time

The client must not play packets immediately on receipt. Wi-Fi jitter will make channels audibly diverge.

## Clock Model

Use a host-authoritative clock.

- The host is the time source.
- Each client estimates offset and drift relative to the host.
- Audio packets carry a `play-at` timestamp in host time.

PTP is the right conceptual model, but iOS does not expose a turnkey IEEE 1588 stack you can depend on here. For V1, implement a lightweight custom clock-sync exchange over UDP:

- client sends ping with local monotonic timestamp
- host replies with receive and send timestamps in host monotonic time
- client estimates RTT, offset, and drift
- client continuously refines a smoothed host-time projection

## Jitter Buffer

Each client needs a jitter buffer sized in time, not packet count.

Recommended starting targets:

- initial pre-roll: `250 ms`
- target play lead time: `300-500 ms`
- adaptive jitter tolerance: grow to `750 ms` if network instability is detected

The host should stamp packets to play slightly ahead of wall-clock to give the client enough runway.

## Playback Scheduling

On the client:

- convert host `play-at` time to estimated local monotonic time
- translate that into `AVAudioTime`
- schedule the buffer for exact playback

If direct `scheduleBuffer(at:)` proves too brittle under drift, a pull-based render path using `AVAudioSourceNode` plus a time-indexed ring buffer can be more stable than repeatedly scheduling small buffers.

## Rendering Strategy

Prefer a client render engine like:

- `AVAudioEngine`
- `AVAudioPlayerNode` for initial prototypes
- `AVAudioSourceNode` for tighter timing once sync work begins

`AVAudioPlayerNode` is faster to stand up. `AVAudioSourceNode` usually gives better control when packet timing and drift correction become the dominant problem.

## Threading

Keep all non-UI work off the main thread.

Recommended queues:

- audio render queue: decode and packetization
- network receive queue: UDP reads and packet parse
- sync queue: clock estimation and state updates
- main queue: UI state only

Rules:

- never block the audio callback
- never allocate heavily in the render path
- never perform discovery or socket operations on the main thread

## State Model

Shared domain models should include:

- `ChannelID`: `frontLeft`, `frontRight`, `rearLeft`, `rearRight`
- `ClientDevice`: identity, endpoint, status, latency estimate
- `ChannelAssignment`: channel -> device mapping
- `TransportPacket`
- `ClockEstimate`: offset, drift, RTT, confidence
- `PlaybackHealth`: underruns, packet loss, skew

## Phased Build Plan

## Phase 1: Local Decode Proof of Concept

Build only the host-side local pipeline:

- integrate Quark decoding sources
- implement Objective-C++ bridge
- load a stereo QS test file
- decode to four channels
- verify output by writing four mono WAVs or routing to a multichannel output device

Success criteria:

- stable real-time decode at `48 kHz`
- no per-buffer allocations in steady state
- channel separation audibly matches QS expectations

## Phase 2: Discovery and Assignment

Build LAN presence and UI:

- client advertises itself
- host discovers clients
- host UI assigns each logical channel to a device

Success criteria:

- devices appear and disappear cleanly
- assignments persist for the session
- stale endpoints recover after reconnect

## Phase 3: UDP Audio Transport

Add real packet delivery without full sync sophistication:

- send one mono stream from host to one client
- client buffers and plays with a large fixed delay
- validate packet format, loss behavior, and throughput

Success criteria:

- continuous playback over Wi-Fi
- no main-thread audio work
- buffer survives minor packet jitter

## Phase 4: Clock Sync and Multi-Device Playback

Add host clock sync and scheduled playback:

- implement sync protocol
- stamp packets with `play-at` times
- tune jitter buffer and drift correction
- expand to multiple simultaneous clients

Success criteria:

- inter-device skew consistently below audible threshold
- client drift correction runs without glitches
- packet loss degrades gracefully

## Phase 5: Compression and Hardening

Only add compression after the PCM path is stable.

Candidate codecs:

- Opus for low-latency efficiency
- AAC-ELD if Apple platform tooling makes it easier

This should be a later optimization, not part of initial bring-up.

## Risks and Constraints

- Quark is JUCE-oriented, so some extraction work is unavoidable.
- iOS timing precision is good, but cross-device sync on consumer Wi-Fi is still the hardest part.
- Background execution limits may affect client reliability if the app is not in an active audio session.
- Bluetooth and AirPlay outputs add extra latency variance and should be excluded from V1.
- Simulator testing is not sufficient for transport and sync validation; this needs real devices on the same LAN.

## Practical First Implementation

The fastest path to a working prototype is:

1. Build one iOS app with Host and Client modes.
2. Get local file decode working first.
3. Send only one mono channel over UDP to one client.
4. Use a large fixed buffer delay.
5. Add clock sync only after transport is proven stable.

That sequence removes most unknowns before the difficult distributed-timing work starts.
