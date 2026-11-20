//go:build windows

package collector

import (
	"context"
	"errors"
	"fmt"

	"github.com/yusufpapurcu/wmi"
)

// msftNetAdapter lists the MSFT_NetAdapter properties we use. Fields a given
// Windows build does not expose are tolerated (ErrFieldMismatch).
type msftNetAdapter struct {
	Name                       string
	InterfaceDescription       string
	HardwareInterface          bool
	Speed                      uint64
	Status                     string
	InterfaceOperationalStatus uint32
	MediaConnectState          uint32
}

// listAdapters asks WMI (readable without admin) which adapters are physical
// and combines its answer with the OS interface list; the second return value
// is a short diagnostic for the log.
func listAdapters(ctx context.Context) (map[string]adapterInfo, string) {
	heur := heuristicAdapters(ctx)
	var rows []msftNetAdapter
	err := wmi.QueryNamespace("SELECT * FROM MSFT_NetAdapter", &rows, `root\StandardCimv2`)
	var mismatch *wmi.ErrFieldMismatch
	if err != nil && !errors.As(err, &mismatch) {
		return heur, "wmi error: " + err.Error()
	}
	if len(rows) == 0 {
		return heur, "wmi returned no adapters"
	}
	out := map[string]adapterInfo{}
	for _, r := range rows {
		h := heur[r.Name]
		out[r.Name] = adapterInfo{
			Name:        r.Name,
			Description: r.InterfaceDescription,
			Physical:    r.HardwareInterface,
			Connected:   decideConnected(r.Status, r.InterfaceOperationalStatus, r.MediaConnectState, h.Connected),
			SpeedBps:    r.Speed,
			Note: fmt.Sprintf("wmi status=%q oper=%d media=%d hardware=%v | %s",
				r.Status, r.InterfaceOperationalStatus, r.MediaConnectState, r.HardwareInterface, h.Note),
		}
	}
	return out, "wmi ok"
}
