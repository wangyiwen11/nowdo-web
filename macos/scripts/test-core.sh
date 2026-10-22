#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 5 -D STANDALONE_CORE_TESTS Sources/NowDoCore/TimerLedger.swift Tests/NowDoCoreTests/TimerLedgerTests.swift Tests/NowDoCoreTests/StandaloneRunner.swift -o .build/nowdo-core-tests
.build/nowdo-core-tests
