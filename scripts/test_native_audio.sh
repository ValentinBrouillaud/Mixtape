#!/usr/bin/env bash
# Run after `swift build --build-tests`; Python is owned by this shell, so the
# Swift concurrency test workers never need to spawn or wait for the server.
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_parent="${TMPDIR:-/tmp}"
fixture_parent="${fixture_parent%/}"
fixture_root="$(mktemp -d "$fixture_parent/mixtape-audio-tests.XXXXXX")"
ready_file="$fixture_root/ready.json"
media_directory="$fixture_root/media"
fixture_log="${LOG_DIR:-$fixture_root}/audio-fixture.log"
server_pid=''
mkdir -p "$media_directory" "$(dirname "$fixture_log")"

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    for attempt in {1..20}; do
      if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
      sleep 0.1
    done
    if kill -0 "$server_pid" 2>/dev/null; then kill -KILL "$server_pid" 2>/dev/null || true; fi
    wait "$server_pid" 2>/dev/null || true
  fi
  case "$fixture_root" in
    "$fixture_parent"/mixtape-audio-tests.*) rm -rf -- "$fixture_root" ;;
  esac
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

python3 "$repository_root/Tests/NativeAudioTransportTests/Fixtures/http_audio_server.py" \
  --port 0 --ready-file "$ready_file" --media-directory "$media_directory" \
  > "$fixture_log" 2>&1 &
server_pid=$!

# macOS can impose a long first-launch delay on a Python executable. Start it
# once and allow a minute for readiness; individual tests reuse the same server.
for attempt in {1..600}; do
  if [[ -s "$ready_file" ]]; then break; fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    cat "$fixture_log" >&2
    echo 'Audio fixture exited before becoming ready.' >&2
    exit 1
  fi
  sleep 0.1
done
if [[ ! -s "$ready_file" ]]; then
  cat "$fixture_log" >&2
  echo 'Audio fixture did not become ready within 60 seconds.' >&2
  exit 1
fi

MIXTAPE_AUDIO_TEST_SERVER_BASE="$(python3 -c 'import json,sys; print("http://127.0.0.1:" + str(json.load(open(sys.argv[1]))["port"]))' "$ready_file")"
export MIXTAPE_AUDIO_TEST_SERVER_BASE
export MIXTAPE_AUDIO_TEST_MEDIA_DIRECTORY="$media_directory"
echo 'Shell-owned audio fixture ready; running native transport and decode tests.'
swift test --skip-build --package-path "$repository_root" "$@"
