//go:build windows

package collector

import (
	"context"

	"github.com/yusufpapurcu/wmi"
)

type msftPhysicalDisk struct {
	FriendlyName string
	DeviceId     string
	MediaType    uint16
	BusType      uint16
	HealthStatus uint16
	Size         uint64
}

var mediaTypes = map[uint16]string{3: "HDD", 4: "SSD", 5: "SCM"}

var busTypes = map[uint16]string{
	1: "SCSI", 2: "ATAPI", 3: "ATA", 4: "1394", 6: "Fibre Channel", 7: "USB", 8: "RAID", 9: "iSCSI",
	10: "SAS", 11: "SATA", 12: "SD", 13: "MMC", 14: "Virtual", 15: "File-backed virtual",
	16: "Storage Spaces", 17: "NVMe",
}

var healthNames = map[uint16]string{0: "Healthy", 1: "Warning", 2: "Unhealthy"}

// listPhysicalDisks reads MSFT_PhysicalDisk (Storage namespace), which a
// standard user can query. Temperature, wear and power-on hours live in a
// different class that often needs admin, so they are not read here.
func listPhysicalDisks(ctx context.Context) ([]physicalDisk, error) {
	var rows []msftPhysicalDisk
	err := wmi.QueryNamespace(
		"SELECT FriendlyName, DeviceId, MediaType, BusType, HealthStatus, Size FROM MSFT_PhysicalDisk",
		&rows, `root\Microsoft\Windows\Storage`)
	if err != nil {
		return nil, err
	}
	out := make([]physicalDisk, 0, len(rows))
	for _, r := range rows {
		out = append(out, physicalDisk{
			ID:        r.DeviceId,
			Model:     r.FriendlyName,
			MediaType: mediaTypes[r.MediaType],
			BusType:   busTypes[r.BusType],
			Size:      r.Size,
			Health:    healthNames[r.HealthStatus],
		})
	}
	return out, nil
}
