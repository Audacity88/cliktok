#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
tmp_binary="$tmp_dir/cliktok-archive-core-tests"
swiftc cliktok/Models/ArchiveDiscoveryItem.swift cliktok/Services/ArchiveDiscoveryService.swift tests/ArchiveDiscoveryCoreTests.swift -o "$tmp_binary"
"$tmp_binary"
