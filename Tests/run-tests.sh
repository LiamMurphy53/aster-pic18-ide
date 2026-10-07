#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swiftc -swift-version 5 -module-cache-path /private/tmp/aster-swift-cache Sources/Core.swift Tests/Watches.swift -o /private/tmp/aster-watch-tests
/private/tmp/aster-watch-tests "$PWD"
swiftc -swift-version 5 -module-cache-path /private/tmp/aster-swift-cache -framework JavaScriptCore Sources/Core.swift Tests/ProjectFiles.swift -o /private/tmp/aster-project-files
/private/tmp/aster-project-files "$PWD"
swiftc -swift-version 5 -module-cache-path /private/tmp/aster-swift-cache Sources/Core.swift Tests/Lab4.swift -o /private/tmp/aster-lab4-tests
/private/tmp/aster-lab4-tests "$PWD"
swiftc -swift-version 5 -module-cache-path /private/tmp/aster-swift-cache Sources/Core.swift Tests/Bench.swift -o /private/tmp/aster-bench-tests
/private/tmp/aster-bench-tests "$PWD"
swiftc -swift-version 5 -module-cache-path /private/tmp/aster-swift-cache Sources/Core.swift Tests/Integration.swift -o Tests/integration
swiftc -swift-version 5 -module-cache-path /private/tmp/aster-swift-cache Sources/Core.swift Tests/Interrupts.swift -o Tests/interrupts
swiftc -swift-version 5 -module-cache-path /private/tmp/aster-swift-cache Sources/Core.swift Tests/Serial.swift -o Tests/serial
swiftc -swift-version 5 -module-cache-path /private/tmp/aster-swift-cache Sources/Core.swift Tests/Stopwatch.swift -o /private/tmp/aster-stopwatch-tests
swiftc -swift-version 5 -module-cache-path /private/tmp/aster-swift-cache Sources/Core.swift Tests/Programming.swift -o /private/tmp/aster-programming-tests
/private/tmp/aster-programming-tests
Tests/integration "$PWD"
Tests/interrupts "$PWD"
Tests/serial
/private/tmp/aster-stopwatch-tests "$PWD"
