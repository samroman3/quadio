# Quadio
<img width="180" height="180" alt="180" src="https://github.com/user-attachments/assets/3dfe40dc-0b78-4f5c-b141-bdbed4b08c3c" />

Quadio is an iOS app for decoding [QS Regular Matrix](https://en.wikipedia.org/wiki/QS_Regular_Matrix)-encoded stereo audio into four playback channels and distributing those channels across nearby iPhones on the same Wi-Fi network.

The app takes a standard 2-channel stereo source and extracts:
- Front Left
- Front Right
- Rear Left
- Rear Right

From there, one device acts as the host, discovers other devices running the app, and routes each decoded channel to a selected client for playback.

## What It Does

- Decodes QS-encoded stereo audio using a native iOS bridge around the [QS / QUARK decoder core](https://github.com/quarkquad/qs)
- Discovers nearby devices over Wi-Fi
- Assigns each of the four decoded channels to different devices
- Streams low-latency audio between devices
- Includes a built-in sample file for quick end-to-end testing

## Background

[QS Regular Matrix](https://en.wikipedia.org/wiki/QS_Regular_Matrix) is a matrix quadraphonic format originally developed by Sansui for encoding four channels into a stereo-compatible signal. The decoder library used here is based on the open-source [QS library](https://github.com/quarkquad/qs), which is also the core of [QUARK](https://github.com/quarkquad), a project focused on quadraphonic spatial audio workflows.

## Potential Use Cases

- Portable surround sound setups using multiple iPhones and powered speakers
- Art installations with distributed speaker placement
- Vintage quadraphonic playback and listening tests
- Audio restoration and archival workflows for QS material
- Education and demos around matrix-encoded surround formats

## Testing

The app includes a bundled QS test file that can be loaded directly from the host screen with `Use Sample`.

Sample sequence:
- `0–2s`: Front Left
- `2–4s`: Front Right
- `4–6s`: Rear Left
- `6–8s`: Rear Right

When routing is working correctly, each assigned device should only play during its own two-second window.

## Project

- App target: `Quadio`
- Unit test target: `QuadioTests`
- Project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`

## Status

This is a working prototype with:
- native decoder integration
- host/client discovery
- channel routing
- network streaming
- baseline unit tests for packet encoding and jitter buffer behavior

The remaining work for a production-ready release is primarily deeper sync hardening, broader physical-device testing, and general product polish.
