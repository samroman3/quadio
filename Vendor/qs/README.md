# Vendoring `quarkquad/qs`

This directory is reserved for the extracted decoder sources from:

- https://github.com/quarkquad/qs

Current state:

- The Xcode project compiles with a placeholder C++ decoder in `Bridge/QSDecoder/QSDecoderFallback.hpp`.
- Replace that fallback with the real `MultiBandDecoder` integration once the minimal JUCE-independent source subset is copied here.

Recommended next integration step:

1. Copy the required decoder headers and implementation files into this directory.
2. Remove JUCE-only wrappers that are not needed for iOS runtime decode.
3. Update `QSDecoderBridge.mm` to own the real decoder object instead of `QSDecoderFallback`.
