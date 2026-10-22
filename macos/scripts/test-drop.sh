#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 5 Sources/NowDoDot/CalendarDropLoader.swift Tests/NowDoDotTests/CalendarDropLoaderTests.swift -o .build/nowdo-calendar-drop-tests
.build/nowdo-calendar-drop-tests
