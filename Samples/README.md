`qs_test_sequence.wav` is a synthetic QS-encoded stereo test file for Quadio.

It plays one encoded source at a time in this order:

1. `0s-2s`: Front Left tone
2. `2s-4s`: Front Right tone
3. `4s-6s`: Rear Left tone
4. `6s-8s`: Rear Right tone

Use it to verify that:

- the host imports and decodes correctly
- each decoded channel can be assigned to a different device
- the correct device plays during its time window

This is a locally generated test asset, not commercial program material.
