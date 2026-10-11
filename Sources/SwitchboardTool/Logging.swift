import os

/// Read with: /usr/bin/log stream --predicate 'subsystem == "io.github.masaakiu.switchboardtool"' --level info
let logger = Logger(subsystem: "io.github.masaakiu.switchboardtool", category: "agent")
