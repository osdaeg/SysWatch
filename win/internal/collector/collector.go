// Package collector holds one collector per SysWatch module. Collectors only
// build writer.Output values; scheduling and file output live elsewhere.
package collector

import (
	"context"
	"math"
	"strconv"
	"strings"
	"time"

	"syswatch-win/internal/config"
	"syswatch-win/internal/state"
	"syswatch-win/internal/store"
	"syswatch-win/internal/writer"
)

// Version is written to module_version in every state.
const Version = "0.1.0"

// Default module.order values (cpu 30, memory 40 and disk 60 come from the
// Linux modules; the others still have to be matched against Linux).
const (
	OrderAbout   = 10
	OrderCPU     = 30
	OrderMemory  = 40
	OrderNetwork = 50
	OrderNetTot  = 55
	OrderDisk    = 60
	OrderSmart   = 70
	OrderTop     = 900
)

// Thresholds (>=).
const (
	cpuWarn, cpuCrit   = 80.0, 95.0
	memWarn, memCrit   = 80.0, 95.0
	diskWarn, diskCrit = 85.0, 95.0
)

// Env is what every collector needs; it is rebuilt when the settings change.
type Env struct {
	Cfg   *config.Config
	Mod   *config.Module
	Host  string // host name as shown in sw_hostname
	T     func(string) string
	Store *store.Store
	Now   func() time.Time
}

// Meta identifies a module in a fallback (UNKNOWN) state.
type Meta struct {
	Icon  string
	Label string // English, translated by the scheduler
	Order int
}

// Result is what one collection cycle produced.
type Result struct {
	Outputs []writer.Output
	Remove  []string // state names to delete (e.g. a drive that disappeared)
}

// Collector is one module.
type Collector interface {
	Name() string
	Meta() Meta
	Collect(ctx context.Context) (Result, error)
}

// newState starts a state with module identity, host block and timestamp.
func (e *Env) newState(icon, label string, order int) *state.State {
	st := state.New()
	st.SetModule(icon, label, order, Version)
	st.SetHost(e.Host, e.T("Host"), false)
	st.SetTimestamp(e.Now())
	return st
}

// newEphemeral is like newState without timestamp (short-lived cards).
func (e *Env) newEphemeral(icon, label string, order int) *state.State {
	st := state.New()
	st.SetModule(icon, label, order, Version)
	st.SetHost(e.Host, e.T("Host"), false)
	return st
}

// setStatus writes status and the persisted status_since.
func (e *Env) setStatus(st *state.State, name, status string) {
	st.Set("status", status)
	st.Set("status_since", e.Store.StatusSince(name, status, e.Now()))
}

// Fallback builds the minimal UNKNOWN state used when a collector fails.
func (e *Env) Fallback(name string, m Meta) writer.Output {
	st := e.newState(m.Icon, e.T(m.Label), m.Order)
	e.setStatus(st, name, state.Unknown)
	return writer.Output{Name: name, State: st, IntervalS: e.Mod.IntervalS}
}

func itoa(n int64) string { return strconv.FormatInt(n, 10) }

func clampPct(f float64) int64 {
	n := int64(math.Round(f))
	if n < 0 {
		return 0
	}
	if n > 100 {
		return 100
	}
	return n
}

func trimExe(name string) string {
	if len(name) > 4 && strings.EqualFold(name[len(name)-4:], ".exe") {
		return name[:len(name)-4]
	}
	return name
}
