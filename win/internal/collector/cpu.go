package collector

import (
	"context"
	"fmt"
	"sync"

	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/load"

	"syswatch-win/internal/state"
	"syswatch-win/internal/writer"
)

// CPU collects usage, cores and (estimated) load; optionally a top-processes card.
type CPU struct {
	env       *Env
	top       *topCPUSampler
	mu        sync.Mutex
	topActive bool // a card may exist in the destination
}

// NewCPU creates the CPU collector.
func NewCPU(env *Env) *CPU {
	cores, _ := cpu.Counts(true)
	c := &CPU{env: env, topActive: true} // first cycle clears any stale card
	if env.Mod.TopProcesses {
		c.top = newTopCPUSampler(cores)
	}
	_, _ = cpu.Percent(0, false) // prime the delta
	return c
}

func (c *CPU) Name() string { return "cpu" }
func (c *CPU) Meta() Meta   { return Meta{Icon: "lucide/cpu", Label: "CPU", Order: OrderCPU} }

func (c *CPU) Collect(ctx context.Context) (Result, error) {
	e := c.env
	pct, err := cpu.PercentWithContext(ctx, 0, false)
	if err != nil || len(pct) == 0 {
		return Result{}, fmt.Errorf("cpu usage: %v", err)
	}
	usage := clampPct(pct[0])
	cores, _ := cpu.CountsWithContext(ctx, true)

	st := e.newState("lucide/cpu", e.T("CPU"), OrderCPU)
	st.AddField(state.Field{Key: "usage", Value: itoa(usage), Label: e.T("Usage"), Order: 10, Unit: "%",
		Widget: "line", Min: state.Num(0), Max: state.Num(100), Scale: "fixed",
		Warning: state.Num(cpuWarn), Critical: state.Num(cpuCrit)})
	if cores > 0 {
		st.AddField(state.Field{Key: "cores", Value: itoa(int64(cores)), Label: e.T("Cores"), Order: 15})
	}
	if avg, err := load.AvgWithContext(ctx); err == nil && avg != nil {
		st.AddField(state.Field{Key: "load1", Value: fmt.Sprintf("%.2f", avg.Load1), Label: e.T("Estimated load: 1 minute"), Order: 20})
		st.AddField(state.Field{Key: "load5", Value: fmt.Sprintf("%.2f", avg.Load5), Label: e.T("Estimated load: 5 minutes"), Order: 30})
		st.AddField(state.Field{Key: "load15", Value: fmt.Sprintf("%.2f", avg.Load15), Label: e.T("Estimated load: 15 minutes"), Order: 40})
	}
	status := state.Level(float64(usage), cpuWarn, cpuCrit)
	e.setStatus(st, "cpu", status)

	res := Result{Outputs: []writer.Output{{
		Name: "cpu", State: st, Series: map[string]int64{"usage": usage},
		IntervalS: e.Mod.IntervalS, CSVPoints: e.Mod.CSVPoints,
	}}}

	if c.top != nil {
		rows := c.top.Sample(ctx, e.Now())
		c.mu.Lock()
		defer c.mu.Unlock()
		if status != state.OK {
			card := e.buildTopCard("cpu_top", rankByName(rows, TopN), "%", status,
				func(v float64) string { return fmt.Sprintf("%.1f", v) })
			res.Outputs = append(res.Outputs, card)
			c.topActive = true
		} else if c.topActive {
			res.Remove = append(res.Remove, "cpu_top")
			c.topActive = false
		}
	}
	return res, nil
}
