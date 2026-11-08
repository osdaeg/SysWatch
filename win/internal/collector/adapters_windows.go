//go:build windows

package collector

import (
	"context"

	"github.com/yusufpapurcu/wmi"
)

type msftNetAdapter struct {
	Name                 string
	InterfaceDescription string
	HardwareInterface    bool
	Speed                uint64
	Status               string
}

// listAdapters asks WMI (MSFT_NetAdapter, readable without admin) which
// adapters are physical and connected; interface flags are the fallback.
func listAdapters(ctx context.Context) map[string]adapterInfo {
	var rows []msftNetAdapter
	err := wmi.QueryNamespace(
		"SELECT Name, InterfaceDescription, HardwareInterface, Speed, Status FROM MSFT_NetAdapter",
		&rows, `root\StandardCimv2`)
	if err != nil || len(rows) == 0 {
		return heuristicAdapters(ctx)
	}
	out := map[string]adapterInfo{}
	for _, r := range rows {
		out[r.Name] = adapterInfo{
			Name:      r.Name,
			Physical:  r.HardwareInterface,
			Connected: r.Status == "Up",
			SpeedBps:  r.Speed,
		}
	}
	return out
}
