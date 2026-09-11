# SysWatch

> Watching your homelab, quietly.
> Lightweight, modular and dependency-free monitoring for Linux homelabs.

## Overview

SysWatch is a lightweight monitoring tool designed specifically for Linux homelabs.

Instead of running as a permanent service, SysWatch is executed periodically by cron. Each execution collects system information, runs a set of independent monitoring modules, detects changes, logs events, sends notifications when necessary, generates a static HTML status page, and then exits.

Its goal is to provide useful monitoring while remaining simple, transparent and easy to extend.

---

## Philosophy

SysWatch follows a few simple principles:

- Keep it simple.
- No resident processes.
- No database required.
- Modular architecture.
- Standard Linux tools whenever possible.
- Everything configurable through `.env`.
- Static HTML instead of dynamic dashboards.
- Easy to understand, easy to debug.

---

## Features

- Modular monitoring system.
- Separate user and root checks.
- Persistent state between executions.
- Change detection.
- Configurable notification backends (Gotify initially).
- Static HTML status page.
- Designed for cron execution.
- Minimal dependencies.

---

## Project Structure

```text
syswatch/
├── README.md
├── LICENSE
├── .env.example
├── syswatch-user.sh
├── syswatch-root.sh
│
├── docs/
│   └── ARCHITECTURE.md
│
├── lib/
│
├── modules-user/
├── modules-root/
│
├── state/
├── logs/
├── cache/
├── html/
└── hooks/
```

---

## Configuration

SysWatch is configured through a single `.env` file.

Typical configuration options include:

- Logging
- Notification settings
- Thresholds
- HTML generation
- Directory locations

An example configuration is provided in `.env.example`.

---

## Execution

The intended execution model is:

```text
cron
   │
   ▼
syswatch-user.sh
syswatch-root.sh
   │
   ▼
Modules
   │
   ▼
Logs
State
Notifications
Static HTML
```

No daemon remains running after execution.

---

## Modules

Modules are small Bash scripts responsible for a single monitoring task.

Examples:

- CPU usage
- Memory usage
- Disk usage
- Running processes
- Docker containers
- SMART information
- Services
- Certificates
- Backup verification

New modules can be added without modifying the SysWatch core.

---

## Roadmap

- [x] Project structure
- [x] Core libraries
- [ ] Launcher
- [ ] Module loader
- [ ] Scheduler
- [ ] State management
- [ ] Notification system
- [ ] HTML generator
- [ ] CPU module
- [ ] Memory module
- [ ] Docker module
- [ ] Security modules

---

## Requirements

- Bash
- Standard GNU/Linux utilities
- Cron

Additional optional tools may be used by specific modules.

---

## License

MIT License.

---

## Design Goals

SysWatch aims to be:

- Lightweight
- Predictable
- Modular
- Transparent
- Easy to maintain
- Easy to extend

Rather than replacing enterprise monitoring solutions, SysWatch focuses on providing practical and understandable monitoring for personal Linux servers and homelabs.