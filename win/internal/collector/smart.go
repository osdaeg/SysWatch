package collector

import (
	"context"

	"syswatch-win/internal/state"
	"syswatch-win/internal/writer"
)

// physicalDisk is basic health data for one physical drive.
type physicalDisk struct {
	ID        string
	Model     string
	MediaType string // SSD, HDD, ...
	BusType   string // SATA, NVMe, USB, ...
	Size      uint64
	Health    string // Healthy, Warning, Unhealthy or ""

	// Optional reliability counters; -1 = not available without admin.
	TempC        int
	WearPct      int
	PowerOnHours int64
}

// Smart reports basic disk health without admin rights.
type Smart struct {
	env      *Env
	lastNote string
}

// NewSmart creates the SMART collector.
func NewSmart(env *Env) *Smart { return &Smart{env: env} }

func (s *Smart) Name() string { return "smart" }
func (s *Smart) Meta() Meta {
	return Meta{Icon: "lucide/heart-pulse", Label: "SMART", Order: OrderSmart}
}

func healthStatus(h string) string {
	switch h {
	case "Healthy":
		return state.OK
	case "Warning":
		return state.Warning
	case "Unhealthy":
		return state.Critical
	}
	return state.Unknown
}

func (s *Smart) Collect(ctx context.Context) (Result, error) {
	e := s.env
	disks, note, err := listPhysicalDisks(ctx)
	if err != nil {
		return Result{}, err
	}
	if note != s.lastNote {
		s.lastNote = note
		e.logf("smart: %s", note)
	}
	var res Result
	for _, d := range disks {
		name := "smart_" + writer.Slug(d.ID)
		st := e.newState("lucide/heart-pulse", d.Model, e.order(OrderSmart))
		health := d.Health
		if health == "" {
			health = "Unknown"
		}
		st.AddField(state.Field{Key: "health", Value: e.T(health), Label: e.T("Health"), Order: 10})
		st.AddField(state.Field{Key: "model", Value: d.Model, Label: e.T("Model"), Order: 20})
		if d.MediaType != "" {
			st.AddField(state.Field{Key: "media_type", Value: d.MediaType, Label: e.T("Media type"), Order: 30})
		}
		if d.BusType != "" {
			st.AddField(state.Field{Key: "bus_type", Value: d.BusType, Label: e.T("Bus"), Order: 40})
		}
		if d.Size > 0 {
			st.AddField(state.Field{Key: "size", Value: itoa(int64(d.Size)), Label: e.T("Size"), Order: 50, Render: "bytes"})
		}
		if d.TempC > 0 && d.TempC < 150 {
			st.AddField(state.Field{Key: "temperature", Value: itoa(int64(d.TempC)), Label: e.T("Temperature"), Order: 60, Unit: "°C"})
		}
		if d.WearPct >= 0 && d.WearPct <= 100 {
			st.AddField(state.Field{Key: "wear", Value: itoa(int64(d.WearPct)), Label: e.T("Wear"), Order: 70, Unit: "%"})
		}
		if d.PowerOnHours > 0 {
			st.AddField(state.Field{Key: "power_on_hours", Value: itoa(d.PowerOnHours), Label: e.T("Power-on hours"), Order: 80, Unit: "h"})
		}
		e.setStatus(st, name, healthStatus(d.Health))
		res.Outputs = append(res.Outputs, writer.Output{Name: name, State: st, IntervalS: e.Mod.IntervalS})
	}
	return res, nil
}
