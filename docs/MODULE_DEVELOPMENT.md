# SysWatch Module Development Guide

## Overview

A SysWatch module is an independent script responsible for collecting,
analyzing and publishing information about a single resource or service.

Modules do **not** generate HTML, notifications or events directly.
They only expose structured information through the SysWatch framework.

The framework is responsible for presentation, history, logging,
notifications and event processing.

# Design principles

Every module should follow these principles:

- One module, one responsibility.
- Modules expose data, never presentation.
- Raw data is collected first, analyzed later.
- State is the only communication channel with the framework.
- HTML generation belongs to the framework.
- History belongs to the framework.
- Notifications belong to the framework.
- Modules should be deterministic whenever possible.
- Modules should avoid unnecessary external processes.

---

# Module lifecycle

Every module follows the same execution flow.

```
sw_module_run()

    ↓

collect()

    ↓

analyze()

    ↓

update_state()

    ↓

(optional)
update_history()

    ↓

report()
```

## collect()

Obtains raw data.

Responsibilities:

- Read system information.
- Query APIs.
- Read files.
- Validate external data.
- Never make status decisions.

Example:

```bash
cpu_collect()
weather_collect()
iss_collect()
```

---

## analyze()

Transforms raw data into meaningful information.

Responsibilities:

- Calculate percentages.
- Compare thresholds.
- Determine module status.
- Format values when required.

Example:

```text
CPU_USAGE=82

↓

CPU_STATUS=WARNING
```

---

## update_state()

Publishes module information.

Only this function should write to the module state.

Typical information:

- Current value
- Labels
- Units
- Widget configuration
- Status
- Module metadata

---

## update_history()

Optional.

Stores historical samples.

Example:

```bash
sw_csv_append \
    "cpu" \
    "usage" \
    "${CPU_USAGE}"
```

---

## report()

Logs execution results.

This function should never modify state.

Example:

```bash
sw_log_info \
    "${MODULE_NAME}" \
    "CPU usage ${CPU_USAGE}% (${CPU_STATUS})"
```

---

# Recommended module layout

```bash
readonly MODULE_NAME="cpu"
readonly MODULE_VERSION="1.0.0"

...

cpu_collect()

cpu_analyze()

cpu_update_state()

cpu_update_history()

cpu_report()

sw_module_run()
```

# Module structure

Every SysWatch module should follow the same structure.

```
Configuration
↓
Constants
↓
Global variables
↓
Private functions
    collect()
    analyze()
    update_state()
    update_history() (optional)
    report()
↓
Entry point
```

This layout improves readability and keeps every module consistent across the project.

---

## Configuration

Configuration values should be read only once during module initialization.

Example:

```bash
readonly CPU_WARNING="${CPU_WARNING:-80}"
readonly CPU_CRITICAL="${CPU_CRITICAL:-90}"
```

---

## Constants

Constants should be declared using `readonly`.

Examples:

```bash
readonly MODULE_NAME="cpu"
readonly MODULE_VERSION="1.0.0"
```

---

## Global variables

Global variables store the current execution state of the module.

Use descriptive names prefixed with the module name.

Good examples:

```bash
CPU_USAGE
CPU_LOAD
CPU_STATUS

MEMORY_USAGE
MEMORY_TOTAL

ISS_VISIBLE
ISS_MINUTES_REMAINING
```

Avoid generic names such as:

```bash
status
value
result
data
```

---

## Private functions

Functions should perform a single responsibility.

Recommended order:

```text
collect()
analyze()
update_state()
update_history()
report()
```

Each function should remain small and focused.

---

## Entry point

Every module should expose a single public entry point.

Example:

```bash
sw_module_run() {

    cpu_collect
    cpu_analyze
    cpu_update_state
    cpu_update_history
    cpu_report

}
```

No other function should be called directly from outside the module.

## Coding conventions

Modules should follow these conventions:

- Use four-space indentation.
- Prefer long and descriptive variable names.
- Declare constants using `readonly`.
- Quote every variable expansion unless arithmetic expansion is required.
- Use `local` for function variables.
- One responsibility per function.
- Prefer framework helper functions over direct shell commands.
- Never write HTML directly.
- Never modify another module's state.
- Log meaningful events only.

# State management

The module state is the communication channel between a module and the
SysWatch framework.

Every module stores its current status in a state file using the helper
functions provided by the framework.

Modules should never write state files directly.

---

## Writing state

Always use the helper functions.

Example:

```bash
sw_state_set "usage" "${CPU_USAGE}"
sw_state_set "status" "${CPU_STATUS}"
```

---

## Widget metadata

Widget properties are stored using the following convention:

```text
<key>.property
```

Example:

```bash
sw_state_set "usage.label" "Usage"
sw_state_set "usage.unit" "%"
sw_state_set "usage.widget" "line"
sw_state_set "usage.order" "10"
```

---

## Supported properties

| Property | Description |
|----------|-------------|
| `.label` | Widget title |
| `.unit` | Value unit |
| `.widget` | Widget type |
| `.order` | Display order |
| `.history` | CSV metric name |
| `.display` | Human-readable value |
| `.scale` | Graph scale mode |
| `.warning` | Warning threshold |
| `.critical` | Critical threshold |
| `.min` | Fixed minimum value |
| `.max` | Fixed maximum value |
| `.hidden` | Hide widget |

---

## Widget types

Currently supported widgets:

| Widget | Description |
|---------|-------------|
| `text` | Displays a formatted value |
| `line` | Displays a sparkline with history |

---

## Graph scaling

Line widgets support three scaling modes.

### dynamic

Uses the minimum and maximum values found in the current history.

Recommended for:

- CPU usage
- Network traffic
- Memory usage

---

### zero

Uses zero as the minimum value and the historical maximum as the upper bound.

Recommended for countdowns and metrics where zero has semantic meaning.

Example:

```bash
sw_state_set "minutes_remaining.scale" "zero"
```

---

### fixed

Uses fixed limits.

Example:

```bash
sw_state_set "temperature.scale" "fixed"
sw_state_set "temperature.min" "0"
sw_state_set "temperature.max" "100"
```

---

## Display values

Some metrics have an internal numeric representation but should be shown
using a human-friendly format.

Use the `.display` property.

Example:

```bash
minutes_remaining=1128
minutes_remaining.display=18 h 48 min
```

The numeric value is still used for:

- Graphs
- Thresholds
- History
- Events

The display value is only used by the HTML renderer.

---

## Hidden values

Widgets can be hidden from the dashboard.

```bash
sw_state_set "temperature.hidden" "true"
```

Hidden values remain available for:

- Events
- Notifications
- Other framework components

# Framework helpers

SysWatch provides a set of helper functions that should be used instead of
direct shell commands whenever possible.

Using the framework helpers keeps modules consistent and allows the
framework to evolve without changing individual modules.

---

# State helpers

State helpers are used to read and write module state.

## Select a state file

```bash
sw_state_use "cpu"
```

---

## Load state

```bash
sw_state_load
```

Loads the current module state into memory.

---

## Save state

```bash
sw_state_save
```

Writes all pending changes to disk.

---

## Read a value

```bash
value="$(sw_state_get "usage")"
```

---

## Write a value

```bash
sw_state_set "usage" "${CPU_USAGE}"
```

---

## Status helpers

Update module status.

```bash
sw_status_update "${CPU_STATUS}"
```

The framework automatically updates:

- status
- timestamp
- status_since

---

# CSV helpers

CSV helpers store historical information.

## Append a sample

```bash
sw_csv_append \
    "cpu" \
    "usage" \
    "${CPU_USAGE}"
```

---

## Read history

```bash
sw_csv_last_values \
    "cpu" \
    "usage" \
    10
```

Returns the latest samples in chronological order.

---

# Cache helpers

Cache helpers avoid unnecessary external requests.

## Check cache

```bash
sw_cache_exists "weather.json"
```

---

## Cache age

```bash
sw_cache_age "weather.json"
```

Returns the cache age in seconds.

---

## Read cache

```bash
sw_cache_read "weather.json"
```

---

## Write cache

```bash
sw_cache_write \
    "weather.json" \
    "${response}"
```

---

## Remove cache

```bash
sw_cache_remove "weather.json"
```

---

# Logging helpers

Modules should never use echo for logging.

Always use the logging helpers.

## Debug

```bash
sw_log_debug \
    "${MODULE_NAME}" \
    "Message"
```

---

## Info

```bash
sw_log_info \
    "${MODULE_NAME}" \
    "Message"
```

---

## Warning

```bash
sw_log_warning \
    "${MODULE_NAME}" \
    "Message"
```

---

## Error

```bash
sw_log_error \
    "${MODULE_NAME}" \
    "Message"
```

---

## Critical

```bash
sw_log_critical \
    "${MODULE_NAME}" \
    "Message"
```

---

# Event helpers

Events are generated by the framework.

Modules should expose state and let the framework decide whether an event
must be created.

Avoid generating events directly unless absolutely necessary.

---

# Utility helpers

The framework also provides reusable utility functions.

Examples include:

- Value formatting
- Time formatting
- String helpers
- Validation helpers

Prefer these helpers over custom implementations whenever available.

# Performance guidelines

Modules are executed periodically.

Keep execution time as low as possible.

Recommendations:

- Reuse cached data whenever possible.
- Avoid unnecessary forks.
- Avoid repeated calls to jq.
- Avoid repeated calls to date.
- Read external resources only once.
- Keep helper functions pure whenever possible.
- Prefer framework helpers over custom code.
- Never perform expensive work inside update_state().
# Best practices

The following recommendations summarize the design philosophy of SysWatch
modules.

Following these guidelines keeps modules simple, maintainable and
consistent across the project.

---

## One module, one responsibility

A module should monitor a single resource or service.

Good examples:

- CPU
- Memory
- Disk
- Weather
- ISS

Avoid combining unrelated metrics into the same module.

---

## Separate collection from analysis

Collect raw data first.

Analyze it afterwards.

Good:

collect()

↓

analyze()

Bad:

Collect data while simultaneously deciding status.

---

## Keep functions focused

Every function should have a single responsibility.

Prefer:

cpu_collect()
cpu_analyze()

Instead of:

cpu_do_everything()

---

## Use framework helpers

Prefer SysWatch helper functions over custom implementations.

Good:

sw_state_set()
sw_csv_append()
sw_cache_read()

Avoid:

echo >> statefile

---

## Never write framework files directly

Modules should never manipulate:

- State files
- CSV files
- Cache files
- HTML

Always use the framework API.

---

## Validate external data

Every API response should be validated.

Examples:

- HTTP errors
- Empty responses
- Invalid JSON
- Missing fields

Never assume external data is correct.

---

## Cache expensive operations

Use the cache whenever possible.

Good candidates:

- Weather APIs
- ISS API
- Speed tests
- DNS lookups

---

## Keep modules deterministic

The same input should always produce the same output.

Avoid hidden side effects.

---

## Prefer readable code

Readability is more important than clever Bash tricks.

Good code should explain itself.

---

## Minimize external processes

Avoid unnecessary executions of:

- jq
- awk
- sed
- grep
- date

Read once.

Process once.

Reuse results.

---

## Fail gracefully

Modules should never crash the framework.

If data cannot be collected:

- Log the problem.
- Return UNKNOWN when appropriate.
- Keep the framework running.

---

## Use meaningful names

Prefer:

CPU_USAGE

Instead of:

usage

Prefer:

iss_collect()

Instead of:

collect()

---

## Keep presentation outside the module

Modules generate information.

The framework generates presentation.

Do not create HTML inside modules.

Do not format terminal output unless intended for logging.

---

## Version every module

Every module should expose its own version.

Example:

```bash
readonly MODULE_VERSION="1.0.0"
```

This simplifies debugging and future migrations.

---

## Think framework first

If a feature could benefit multiple modules,
consider implementing it in the framework instead of a single module.

Examples:

- Cache helpers
- CSV helpers
- Display formatting
- Graph scaling
- Logging

A SysWatch module should describe reality, not presentation.
A module answers "what is happening?"
The framework decides "how to present it."
