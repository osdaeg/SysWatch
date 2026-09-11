SysWatch Architecture

Purpose

SysWatch is a lightweight, modular monitoring framework for Linux systems.

Its purpose is to monitor system health using small, independent modules that execute periodically, collect information, evaluate system status, generate events and exit.

Unlike traditional monitoring platforms, SysWatch does not rely on long-running daemons, databases or complex infrastructures. Every execution is independent, deterministic and stateless, with persistent information stored in simple text files.

The project prioritizes simplicity, readability and maintainability over feature richness.

---

Architecture Goals

The architecture of SysWatch is guided by a small number of fundamental goals.

Simplicity

The implementation should remain understandable to any developer familiar with Bash and standard Unix tools.

Complex solutions should only be introduced when they provide a clear benefit.

Whenever possible, simple designs are preferred over clever ones.

---

Modularity

Every monitoring feature is implemented as an independent module.

Modules should be isolated from one another and should communicate with the framework only through its public interfaces.

Adding a new module should require copying a single file into the appropriate modules directory.

---

Predictability

Every execution follows the same lifecycle.

The same inputs should always produce the same outputs.

Modules must not depend on execution order or on the internal implementation of other modules.

---

Human-readable Data

All generated data should be readable without specialized software.

Logs, events and state files are intended to be inspected directly using standard Unix tools.

This simplifies troubleshooting, backups and manual inspection.

---

Minimal Dependencies

SysWatch should rely primarily on Bash and standard Linux kernel interfaces such as "/proc" and "/sys".

External utilities should only be used when they provide significant value or when no reasonable alternative exists.

---

Stateless Execution

SysWatch is not a daemon.

Each execution starts from a clean environment, loads any required persistent information, performs its work and exits immediately.

Persistent information is stored on disk using simple text files.

This approach minimizes resource usage while keeping the execution model simple and predictable.

---

Core Principles

The following principles define the architecture of SysWatch.

Framework and Modules

SysWatch is divided into two major components:

- the framework;
- the monitoring modules.

The framework provides the execution environment.

Modules provide the monitoring logic.

The framework is responsible for:

- loading configuration;
- discovering modules;
- persistent state management;
- event generation;
- logging;
- status management;
- HTML generation.

Modules are responsible for:

- collecting information;
- analyzing collected data;
- determining their own health status;
- updating module-specific persistent metrics.

Modules should never implement framework functionality.

---

Self-contained Modules

Modules should be self-contained.

Each module defines its own default configuration values.

Users may optionally override those defaults through the ".env" file.

The SysWatch core should never require modification when a new module is added.

---

Stable Interfaces

Modules communicate with the framework exclusively through its public APIs.
The framework may evolve internally without affecting existing modules.

Examples include:

- "sw_log_*()"
- "sw_event_*()"
- "sw_state_*()"
- "sw_module_run()"

Modules should never depend on internal implementation details.

---

Separation of Responsibilities

Each library has a single, clearly defined responsibility.

Examples include:

- "logger.sh" manages logging.
- "events.sh" manages events.
- "state.sh" manages persistent state.
- "modules.sh" discovers and executes modules.

Responsibilities should not overlap.

---

Avoid Premature Abstraction

Common functionality should only be extracted after multiple real implementations demonstrate a clear and stable pattern.

This principle keeps the framework simple, avoids unnecessary complexity and allows abstractions to emerge naturally from practical experience.

High-Level Architecture

At a high level, SysWatch consists of a small execution framework and a collection of independent monitoring modules.

                 cron
                  │
                  ▼
          syswatch_user
          syswatch_root
                  │
                  ▼
        Load configuration
                  │
                  ▼
         Initialize framework
                  │
                  ▼
         Discover modules
                  │
                  ▼
      Execute enabled modules
                  │
                  ▼
     Generate state and events
                  │
                  ▼
          Generate HTML
                  │
                  ▼
                Exit

The framework provides the execution environment while modules provide the monitoring logic.

No component remains resident in memory after execution completes.

---

Project Structure

A typical SysWatch installation is organized as follows:

syswatch/

├── syswatch_user
├── syswatch_root
├── .env
│
├── lib/
│   ├── common.sh
│   ├── config.sh
│   ├── logger.sh
│   ├── state.sh
│   ├── events.sh
│   ├── modules.sh
│   └── ...
│
├── modules-user/
├── modules-root/
│
├── state/
├── locks/
├── logs/
├── cache/
└── html/

Each directory has a single, well-defined purpose.

---

Execution Flow

Every execution follows the same lifecycle.

Launcher
    │
    ▼
Load libraries
    │
    ▼
Load configuration
    │
    ▼
Acquire execution lock
    │
    ▼
Initialize runtime
    │
    ▼
Discover modules
    │
    ▼
Execute modules
    │
    ▼
Generate HTML
    │
    ▼
Exit

This deterministic execution model simplifies debugging, testing and maintenance.

---

Single Instance Execution

Each launcher guarantees that only one instance can execute at a time.

Before initialization, the launcher acquires an operating system file lock using the framework locking API.

If another instance is already running, the new execution exits immediately without executing any modules.

This prevents concurrent writes to persistent state, logs, events and generated HTML while keeping the implementation simple and relying on standard Linux file locking mechanisms.

---

Launchers

SysWatch provides two independent launchers.

syswatch_user

Executes monitoring tasks that do not require elevated privileges.

This launcher is intended to run from the user's crontab.

Typical modules include:

- CPU
- Memory
- Disk usage
- User services

---

syswatch_root

Executes monitoring tasks requiring root privileges.

This launcher is intended to run from the system crontab or the root user's crontab.

Typical modules include:

- SMART monitoring
- Filesystem health
- RAID status
- System services

---

Both launchers share the same framework and libraries.

Only the available modules and execution privileges differ.

---

Libraries

The "lib/" directory contains the framework implementation.

Each library has a single responsibility.

common.sh

Provides generic helper functions shared across the project.

Examples include:

- timestamps
- filesystem helpers
- common utilities

---

config.sh

Loads the global configuration from ".env".

Provides default values for framework-wide settings.

Module-specific defaults belong inside each module.

---

logger.sh

Provides a consistent logging interface.

All framework components and modules write logs through this library.

---

state.sh

Provides persistent state management.

Modules use this library to store and retrieve information between executions.

---

events.sh

Records significant events generated by modules.

Events represent changes in system state rather than execution details.

---

modules.sh

Discovers available modules and executes them.

The launcher never knows which modules exist.

Module discovery is completely automatic.

---

status.sh

Provides module status management.

The library is responsible for:

- validating status values;
- detecting status transitions;
- updating persistent status information;
- generating status change events.

Modules determine their own status, but never manage status transitions directly.

---

Future libraries should follow the same philosophy:

- one responsibility;
- minimal public API;
- no overlapping functionality.

Modules

Modules implement the actual monitoring logic.

Each module is an independent Bash script responsible for collecting and evaluating a specific aspect of the system.

Examples include:

- CPU
- Memory
- Filesystems
- SMART
- Docker
- SSL certificates

Modules should remain independent from one another.

No module should directly call another module.

---

Module Structure

Every module should follow the same internal organization.

A recommended layout is:

Metadata

Configuration

Module variables

Helper functions

sw_module_run()

Maintaining a consistent structure improves readability and simplifies maintenance across the project.

---

Module Lifecycle

Every module follows the same execution lifecycle.

sw_state_use()

↓

Select the module state context.

---

sw_state_load()

↓

Load the module's persistent state into memory.

---

collect()

↓

Collect raw metrics from the operating system.

This step should not determine the module status.

---

analyze()

↓

Evaluate the collected metrics.

The module determines its current status, typically one of:

- OK
- WARNING
- CRITICAL

Module-specific thresholds are applied during this step.

---

sw_status_update()

↓

Update the module status.

The framework validates the status, detects status transitions, updates persistent status information and generates events when appropriate.

---

update_state()

↓

Update the module-specific state information.

This step stores metrics that are specific to the module, such as CPU usage or memory consumption.

---

sw_state_save()

↓

Persist the complete module state.

The framework writes the updated state to disk, making it available for the next execution.

---

report()

↓

Write descriptive log entries for the current execution.

Reporting should never modify the module state.

The exact implementation may differ between modules, but this sequence is strongly recommended.

Each step has a well-defined responsibility.

---

Persistent State

Persistent state allows modules to compare the current execution with previous executions.

State is loaded into memory at the beginning of module execution and written back only once before the module exits. Modules never manipulate state files directly.

Each module owns an independent persistent state.
The framework currently stores each module state in a single text file.

Example:

state/

    cpu.state
    memory.state
    docker.state

State files use a simple "key=value" format.

Example:

module_version=0.1.0
status=OK
status_since=2026-06-30 19:35:42

usage=17

timestamp=2026-06-30 19:35:42

State files should remain:

- human-readable;
- easy to parse from Bash;
- stable across versions whenever possible.

Modules should only access state through the functions provided by "state.sh".

---

Events

Events represent significant changes in system health.

Unlike logs, events describe something that happened.

Typical events include:

- status changes;
- service failures;
- certificate expiration;
- hardware problems.

Modules generate events through "events.sh".

Modules should never communicate directly with notification backends.

This separation allows new notification mechanisms to be added without modifying existing modules.

---

Logging

Logs describe execution.

Events describe system changes.

Examples of log entries include:

- module started;
- module completed;
- collected value;
- execution errors.

Logs are intended primarily for troubleshooting and auditing.

Every module should use the logging functions provided by "logger.sh".

---

Configuration

Configuration is divided into two categories.

Global Configuration

Framework-wide settings belong in ".env".

Examples include:

- log level;
- directory locations;
- notification settings;
- HTML configuration.

---

Module Configuration

Each module defines its own default configuration values.

Users may override those defaults through ".env".

This approach keeps modules self-contained while allowing customization.

Adding a new module should never require modifications to the framework.

Public APIs

Modules should interact with the framework exclusively through documented public functions.

The framework reserves the right to change internal implementations without affecting modules.

Current public interfaces include:

Locking

sw_lock_acquire()

Acquires an exclusive execution lock for the current launcher.

If another instance is already running, the function terminates the current execution immediately.

Launchers should acquire the execution lock before starting the monitoring cycle.

Logging

sw_log_debug()
sw_log_info()
sw_log_warning()
sw_log_error()
sw_log_critical()

Used to write execution logs.

---

State

sw_state_use()
sw_state_load()
sw_state_get()
Returns a value previously loaded into the module state.
sw_state_set()
Updates the in-memory state.
Changes are persisted only after calling sw_state_save().
sw_state_save()

Used to read and write persistent module state.

Modules should never manipulate state files directly.

---

Events

High-level helper functions such as:

sw_event_info()
sw_event_warning()
sw_event_critical()

are recommended for most modules.

Used to record significant system events.

Notification backends consume events generated through this interface.

---

Module Entry Point

Every module must export a single public entry point:

sw_module_run()

The launcher invokes only this function.

All helper functions remain private to the module.

---

Coding Conventions

The following conventions apply to all framework components and modules.

General

- Use Bash built-ins whenever practical.
- Keep functions small and focused.
- Prefer readability over cleverness.
- Minimize external process execution.
- Follow consistent formatting throughout the project.

---

Naming

Framework functions use the "sw_" prefix.

Examples:

sw_log_info()
sw_state_save()
sw_event()
sw_module_run()

Private helper functions may use descriptive names but should remain local to the module.

---

Variables

Global variables should be avoided whenever possible.

Constants should be declared using:

readonly VARIABLE_NAME="value"

Temporary values should use local variables.

---

Modules

Modules should:

- be self-contained;
- have a single responsibility;
- avoid dependencies on other modules;
- expose only "sw_module_run()".

Module-specific configuration belongs inside the module.

---

Error Handling

Unexpected conditions should be logged.

Recoverable errors should not prevent other modules from executing.

Whenever possible, a failure in one module should not affect the rest of the framework.

---

Design Decisions

The following architectural decisions intentionally shape the project.

Cron instead of Daemons

SysWatch executes periodically from cron.

This eliminates idle resource consumption while keeping execution predictable.

---

Text Files instead of Databases

Persistent information is stored using simple text files.

Benefits include:

- transparency;
- portability;
- easy backups;
- simple parsing from Bash.

---

Independent Modules

Modules never communicate directly with one another.

This minimizes coupling and simplifies testing.

---

Framework-owned Infrastructure

The framework owns:

- configuration;
- state management;
- event generation;
- logging;
- module discovery;
- HTML generation.

Modules own only their monitoring logic.

---

Incremental Abstraction

Abstractions should emerge naturally from real implementations.

Framework libraries should only grow after common patterns have been identified.

---

Future Evolution

The architecture intentionally leaves room for future enhancements.

Potential additions include:

- notification backends;
- historical graphs;
- additional HTML views;
- module dependency metadata;
- scheduling improvements;
- plugin packaging.

Future features should preserve the project's core principles of simplicity, modularity and readability.

---

Conclusion

SysWatch is designed to remain small, understandable and maintainable.

Every architectural decision should reinforce the following principles:

- simplicity over complexity;
- transparency over abstraction;
- modularity over coupling;
- readability over cleverness.

If a proposed change conflicts with these principles, the simpler design should generally be preferred.

