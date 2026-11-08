package collector

import (
	"context"
	"strings"

	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/mem"

	"syswatch-win/internal/state"
	"syswatch-win/internal/writer"
)

// About reports static-ish system facts.
type About struct{ env *Env }

// NewAbout creates the about collector.
func NewAbout(env *Env) *About { return &About{env: env} }

func (a *About) Name() string { return "about" }
func (a *About) Meta() Meta   { return Meta{Icon: "lucide/info", Label: "About", Order: OrderAbout} }

func (a *About) Collect(ctx context.Context) (Result, error) {
	e := a.env
	st := e.newState("lucide/info", e.T("About"), OrderAbout)
	add := func(key, label string, order int, value, unit string) {
		if strings.TrimSpace(value) == "" {
			return
		}
		st.AddField(state.Field{Key: key, Value: strings.TrimSpace(value), Label: e.T(label), Order: order, Unit: unit})
	}
	if hi, err := host.InfoWithContext(ctx); err == nil && hi != nil {
		add("os", "Operating system", 10, hi.Platform, "")
		add("version", "Version", 20, hi.PlatformVersion, "")
		add("arch", "Architecture", 30, hi.KernelArch, "")
	}
	if ci, err := cpu.InfoWithContext(ctx); err == nil && len(ci) > 0 {
		add("cpu_model", "CPU model", 40, ci[0].ModelName, "")
	}
	add("gpu", "GPU", 50, gpuInfo(), "")
	if vm, err := mem.VirtualMemoryWithContext(ctx); err == nil && vm != nil {
		add("memory_total", "Memory", 60, itoa(int64(vm.Total/mib)), "Mb")
	}
	e.setStatus(st, "about", state.OK)
	return Result{Outputs: []writer.Output{{Name: "about", State: st, IntervalS: e.Mod.IntervalS}}}, nil
}
