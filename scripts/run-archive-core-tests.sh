#!/bin/sh
set -eu
tmp_binary="${TMPDIR:-/tmp}/cliktok-archive-core-tests"
swiftc cliktok/Models/ArchiveDiscoveryItem.swift tests/ArchiveDiscoveryCoreTests.swift -o "$tmp_binary"
"$tmp_binary"
