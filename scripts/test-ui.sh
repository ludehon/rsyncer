#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
UI_TEST_BUILD_DIR=$(mktemp -d /tmp/rsyncer-ui-tests.XXXXXX)
trap 'rm -rf "$UI_TEST_BUILD_DIR"' EXIT
swiftc -parse-as-library -module-cache-path "$UI_TEST_BUILD_DIR/cache" \
  rsyncer/Models/SyncPair.swift rsyncer/Services/*.swift \
  rsyncer/ContentView.swift rsyncer/Views/*.swift \
  Tests/ReorderGestureTests.swift -o "$UI_TEST_BUILD_DIR/reorder-tests"
"$UI_TEST_BUILD_DIR/reorder-tests"
