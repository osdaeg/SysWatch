package collector

import (
	"context"
	"fmt"
	"sync"

	"github.com/shirou/gopsutil/v3/mem"

	"syswatch-win/internal/state"
	"syswatch-win/internal/writer"
)

const mib = 1024 * 1024

// Memory collects RAM and pagefile numbers; optionally a top-processes card.
type Memory struct {
	env       *Env
	mu        sync.Mutex
	topActive bool
}

// NewMemory creates the memory collector.
func NewMemory(env *Env) *Memory { return &Memory{env: env, topActive: true} }

func (m *Memory) Name() string { return "memory" }
func (m *Memory) Meta() Meta {
	return Meta{Icon: "lucide/memory", Label: "Memory", Order: OrderMemory}
}

func (m *Memory) Collect(ctx context.Context) (Result, error) {
	e := m.env
	vm, err := mem.VirtualMemoryWithContext(ctx)
	if err != nil || vm == nil || vm.Total == 0 {
		return Result{}, fmt.Errorf("memory: %v", err)
	}
	used := vm.Total - vm.Available
	usage := clampPct(float64(used) * 100 / float64(vm.Total))

	st := e.newState("lucide/memory", e.T("Memory"), OrderMemory)
	st.AddField(state.Field{Key: "usage", Value: itoa(usage), Label: e.T("Used"), Order: 10, Unit: "%",
		Widget: "gauge", Warning: state.Num(memWarn), Critical: state.Num(memCrit)})
	mb := func(key, label string, order int, bytes uint64) {
		st.AddField(state.Field{Key: key, Value: itoa(int64(bytes / mib)), Label: e.T(label), Order: order, Unit: "Mb"})
	}
	mb("total_mb", "Total", 20, vm.Total)
	mb("used_mb", "Used", 30, used)
	mb("available_mb", "Available", 40, vm.Available)
	if sw, err := mem.SwapMemoryWithContext(ctx); err == nil && sw != nil && sw.Total > 0 {
		mb("swap_total_mb", "Swap total", 50, sw.Total)
		mb("swap_used_mb", "Swap used", 60, sw.Used)
		mb("swap_free_mb", "Swap free", 70, sw.Free)
	}
	status := state.Level(float64(usage), memWarn, memCrit)
	e.setStatus(st, "memory", status)

	res := Result{Outputs: []writer.Output{{Name: "memory", State: st, IntervalS: e.Mod.IntervalS}}}

	if e.Mod.TopProcesses {
		m.mu.Lock()
		defer m.mu.Unlock()
		if status != state.OK {
			card := e.buildTopCard("memory_top", rankByName(memoryRows(ctx), TopN), "Mb", status,
				func(v float64) string { return itoa(int64(v + 0.5)) })
			res.Outputs = append(res.Outputs, card)
			m.topActive = true
		} else if m.topActive {
			res.Remove = append(res.Remove, "memory_top")
			m.topActive = false
		}
	}
	return res, nil
}
