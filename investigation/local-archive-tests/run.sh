#!/bin/sh
set -eu

test_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build_root=$(mktemp -d "${TMPDIR:-/tmp}/local-archive-tests.XXXXXX")
trap 'rm -rf "$build_root"' EXIT

swiftc "$test_root/Postbox.swift" "$test_root/../../submodules/Postbox/Sources/MutableBasicPeerView.swift" "$test_root/MutableBasicPeerViewTests.swift" -o "$build_root/local-archive-tests"
"$build_root/local-archive-tests"

uv run --no-project python "$test_root/run_thread_info_test.py"
