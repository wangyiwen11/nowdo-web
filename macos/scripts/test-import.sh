#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 5 -D STANDALONE_IMPORT_TESTS Sources/NowDoCore/CalendarSelection.swift Tests/NowDoCoreTests/CalendarSelectionTests.swift Tests/NowDoCoreTests/CalendarSelectionStandaloneRunner.swift -o .build/nowdo-calendar-import-tests
.build/nowdo-calendar-import-tests
