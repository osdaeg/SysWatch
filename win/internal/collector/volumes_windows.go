//go:build windows

package collector

import (
	"context"

	"github.com/shirou/gopsutil/v3/disk"
	"golang.org/x/sys/windows"
)

// listVolumes returns every drive Windows reports, with its drive type.
func listVolumes(ctx context.Context) ([]volume, error) {
	parts, err := disk.PartitionsWithContext(ctx, true)
	var out []volume
	for _, p := range parts {
		kind := "fixed"
		switch windows.GetDriveType(windows.StringToUTF16Ptr(p.Mountpoint + `\`)) {
		case windows.DRIVE_REMOVABLE:
			kind = "removable"
		case windows.DRIVE_REMOTE:
			kind = "network"
		case windows.DRIVE_CDROM:
			kind = "cdrom"
		case windows.DRIVE_RAMDISK:
			kind = "ram"
		}
		out = append(out, volume{Mount: p.Mountpoint + `\`, Device: p.Device, Fstype: p.Fstype, Kind: kind})
	}
	if len(out) > 0 {
		err = nil // partial warnings are fine when we got drives
	}
	return out, err
}
