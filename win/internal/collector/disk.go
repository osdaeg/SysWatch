package collector

import (
	"context"
	"strings"
	"sync"

	"github.com/shirou/gopsutil/v3/disk"

	"syswatch-win/internal/state"
	"syswatch-win/internal/writer"
)

// volume is a mounted filesystem / drive letter.
type volume struct {
	Mount  string // path to query usage, e.g. `C:\`
	Device string // `C:` on Windows
	Fstype string
	Kind   string // fixed, removable, network, cdrom, ram
}

// Disk produces one state per drive.
type Disk struct {
	env   *Env
	mu    sync.Mutex
	known map[string]bool
}

// NewDisk creates the disk collector.
func NewDisk(env *Env) *Disk { return &Disk{env: env, known: map[string]bool{}} }

func (d *Disk) Name() string { return "disk" }
func (d *Disk) Meta() Meta {
	return Meta{Icon: "lucide/hard-drive", Label: "Disk", Order: OrderDisk}
}

func (d *Disk) wanted(v volume) bool {
	switch v.Kind {
	case "fixed":
		return true
	case "removable":
		return d.env.Mod.IncludeRemovable
	case "network":
		return d.env.Mod.IncludeNetwork
	}
	return false
}

func driveName(v volume) string {
	base := v.Device
	if base == "" {
		base = v.Mount
	}
	slug := writer.Slug(base)
	if slug == "" {
		slug = "root"
	}
	return "disk_" + slug
}

func (d *Disk) Collect(ctx context.Context) (Result, error) {
	e := d.env
	vols, err := listVolumes(ctx)
	if len(vols) == 0 && err != nil {
		return Result{}, err
	}
	var res Result
	seen := map[string]bool{}
	for _, v := range vols {
		if !d.wanted(v) {
			continue
		}
		u, err := disk.UsageWithContext(ctx, v.Mount)
		if err != nil || u.Total == 0 {
			continue // drive not ready
		}
		name := driveName(v)
		if seen[name] {
			continue
		}
		seen[name] = true
		label := strings.TrimSuffix(v.Device, `\`)
		if label == "" {
			label = v.Mount
		}
		st := e.newState("lucide/hard-drive", label, OrderDisk)
		st.Set("_internal.mountpoint", v.Mount)
		st.AddField(state.Field{Key: "fstype", Value: v.Fstype, Label: e.T("Type"), Order: 10})
		bytes := func(key, lbl string, order int, n uint64) {
			st.AddField(state.Field{Key: key, Value: itoa(int64(n)), Label: e.T(lbl), Order: order, Render: "bytes"})
		}
		bytes("total", "Total", 20, u.Total)
		bytes("used", "Used", 30, u.Used)
		bytes("avail", "Available", 40, u.Free)
		pct := clampPct(float64(u.Used) * 100 / float64(u.Total))
		st.AddField(state.Field{Key: "used_pct", Value: itoa(pct), Label: e.T("Used"), Order: 50, Unit: "%",
			Widget: "gauge", Warning: state.Num(diskWarn), Critical: state.Num(diskCrit)})
		st.AddField(state.Field{Key: "mountpoint", Value: v.Mount, Label: e.T("Mount point"), Order: 51, Hidden: true})
		st.AddField(state.Field{Key: "source", Value: strings.TrimSuffix(v.Device, `\`), Label: e.T("Source"), Order: 52, Hidden: true})
		e.setStatus(st, name, state.Level(float64(pct), diskWarn, diskCrit))
		res.Outputs = append(res.Outputs, writer.Output{Name: name, State: st, IntervalS: e.Mod.IntervalS})
	}
	d.mu.Lock()
	for name := range d.known {
		if !seen[name] {
			res.Remove = append(res.Remove, name)
		}
	}
	d.known = seen
	d.mu.Unlock()
	return res, nil
}
