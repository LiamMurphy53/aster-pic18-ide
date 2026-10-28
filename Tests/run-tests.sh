#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
TEST_CACHE=$(mktemp -d /private/tmp/aster-test-cache.XXXXXX)
trap 'rm -rf "$TEST_CACHE"' EXIT
swiftc -swift-version 5 -module-cache-path "$TEST_CACHE" Sources/Core.swift Tests/Lab5.swift -o /private/tmp/aster-lab5-tests
/private/tmp/aster-lab5-tests "$PWD"
xcrun clang -std=c11 -D_DEFAULT_SOURCE -O2 Sources/ad2_capture.c -o /private/tmp/aster-ad2-tests -lm
/private/tmp/aster-ad2-tests self-test
swiftc -swift-version 5 -module-cache-path "$TEST_CACHE" Sources/Core.swift Tests/Watches.swift -o /private/tmp/aster-watch-tests
/private/tmp/aster-watch-tests "$PWD"
swiftc -swift-version 5 -module-cache-path "$TEST_CACHE" -framework JavaScriptCore Sources/Core.swift Tests/ProjectFiles.swift -o /private/tmp/aster-project-files
/private/tmp/aster-project-files "$PWD"
swiftc -swift-version 5 -module-cache-path "$TEST_CACHE" Sources/Core.swift Tests/CProject.swift -o /private/tmp/aster-c-project-tests
/private/tmp/aster-c-project-tests "$PWD"
swiftc -swift-version 5 -module-cache-path "$TEST_CACHE" Sources/Core.swift Tests/Lab4.swift -o /private/tmp/aster-lab4-tests
/private/tmp/aster-lab4-tests "$PWD"
swiftc -swift-version 5 -module-cache-path "$TEST_CACHE" Sources/Core.swift Tests/Bench.swift -o /private/tmp/aster-bench-tests
/private/tmp/aster-bench-tests "$PWD"
swiftc -swift-version 5 -module-cache-path "$TEST_CACHE" Sources/Core.swift Tests/Integration.swift -o Tests/integration
swiftc -swift-version 5 -module-cache-path "$TEST_CACHE" Sources/Core.swift Tests/Interrupts.swift -o Tests/interrupts
swiftc -swift-version 5 -module-cache-path "$TEST_CACHE" Sources/Core.swift Tests/Serial.swift -o Tests/serial
swiftc -swift-version 5 -module-cache-path "$TEST_CACHE" Sources/Core.swift Tests/Stopwatch.swift -o /private/tmp/aster-stopwatch-tests
swiftc -swift-version 5 -module-cache-path "$TEST_CACHE" Sources/Core.swift Tests/Programming.swift -o /private/tmp/aster-programming-tests
/private/tmp/aster-programming-tests
Tests/integration "$PWD"
Tests/interrupts "$PWD"
Tests/serial
/private/tmp/aster-stopwatch-tests "$PWD"
