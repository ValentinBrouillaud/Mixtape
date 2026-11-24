# Native audio verification

Use Xcode 26.2 on macOS. Compile the test package, then run it through the shell
runner so one Python fixture serves all HTTP and generated AAC decode tests:

```bash
swift build --build-tests
bash scripts/test_native_audio.sh
```

The runner starts a loopback server, waits up to 60 seconds for its ready file,
passes its address and temporary media directory to Swift Testing, and terminates
the server on exit. CI captures its output in `audio-fixture.log`. Running
`swift test` directly retains a per-test Process fallback, which has substantial
startup delays on the macOS CI runner.

Fixture self-tests also run without Xcode:

```bash
python3 Tests/NativeAudioTransportTests/Fixtures/http_audio_server.py --self-test
```

Synthetic-response tests exercise transport errors and byte integrity. Generated
AAC tests separately check decoded signal after silence and seeking. These do
not verify YouTube access or sound output on an iPhone.
