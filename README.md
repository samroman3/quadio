# Quadio

Quadio is an iOS app for decoding QS matrix-encoded stereo audio into four playback channels and distributing those channels across nearby iPhones on the same Wi-Fi network.

The app takes a standard 2-channel stereo source, extracts:
- Front Left
- Front Right
- Rear Left
- Rear Right

From there, one device acts as the host, discovers other devices running the app, and routes each decoded channel to a selected client for playback.

## What It Does

- Decodes QS-encoded stereo audio using a native iOS bridge around the Quark decoder core
- Discovers nearby devices over Wi-Fi
- Assigns each of the four decoded channels to a different device
- Streams low-latency audio between devices
- Includes a built-in sample file for quick end-to-end testing

## Potential Use Cases

- Portable surround sound setups using multiple iPhones and powered speakers
- Art installations with distributed speaker placement
- Vintage quadraphonic playback and listening tests
- Audio restoration and archive workflows for QS material
- Education and demos around matrix-encoded surround formats

## Testing

The app includes a bundled QS test file that can be loaded directly from the host screen with `Use Sample`.

Sample sequence:
- `0-2s`: Front Left
- `2-4s`: Front Right
- `4-6s`: Rear Left
- `6-8s`: Rear Right

When routing is working correctly, each assigned device should only play during its own two-second window.

## Project

- App target: `Quadio`
- Unit test target: `QuadioTests`
- Project is generated with XcodeGen from `project.yml`

## Status

This is a working prototype with:
- native decoder integration
- host/client discovery
- channel routing
- network streaming
- baseline unit tests for packet encoding and jitter buffer behavior

The remaining work for a production-grade release would mainly be deeper sync hardening, broader physical-device testing, and additional polish.
