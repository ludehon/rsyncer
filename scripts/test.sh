#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
TEST_BUILD_DIR=$(mktemp -d /tmp/rsyncer-test-build.XXXXXX)
trap 'rm -rf "$TEST_BUILD_DIR"' EXIT
swiftc -parse-as-library -module-cache-path "$TEST_BUILD_DIR/cache" \
  rsyncer/Models/*.swift rsyncer/Services/*.swift \
  Tests/IntegrationTests.swift -o "$TEST_BUILD_DIR/integration-tests"
"$TEST_BUILD_DIR/integration-tests"
