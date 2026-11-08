//go:build !windows

package collector

import (
	"context"

	"github.com/shirou/gopsutil/v3/disk"
)

// listVolumes (non-Windows, used for development and tests) lists real
// filesystems only.
func listVolumes(ctx context.Context) ([]volume, error) {
	parts, err := disk.PartitionsWithContext(ctx, false)
	var out []volume
	for _, p := range parts {
		out = append(out, volume{Mount: p.Mountpoint, Device: p.Device, Fstype: p.Fstype, Kind: "fixed"})
	}
	return out, err
}
