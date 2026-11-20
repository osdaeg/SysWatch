//go:build windows

package collector

import (
	"context"
	"errors"
	"fmt"

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

// msftReliability holds the optional counters; pointers stay nil when the
// drive or driver does not report a value.
type msftReliability struct {
	DeviceId     string
	Temperature  *uint8
	Wear         *uint8
	PowerOnHours *uint32
}

const storageNS = `root\Microsoft\Windows\Storage`

// reliabilityByDisk reads MSFT_StorageReliabilityCounter. Whether a standard
// user may read it depends on the drive and driver, so any failure just means
// "no extra data" and is reported in the note.
func reliabilityByDisk() (map[string]msftReliability, string) {
	var rows []msftReliability
	err := wmi.QueryNamespace("SELECT * FROM MSFT_StorageReliabilityCounter", &rows, storageNS)
	var mismatch *wmi.ErrFieldMismatch
	if err != nil && !errors.As(err, &mismatch) {
		return nil, "reliability counters unavailable: " + err.Error()
	}
	m := map[string]msftReliability{}
	for _, r := range rows {
		m[r.DeviceId] = r
	}
	return m, fmt.Sprintf("reliability counters: %d disks", len(m))
}

// listPhysicalDisks reads MSFT_PhysicalDisk (Storage namespace), which a
// standard user can query, plus the optional reliability counters.
func listPhysicalDisks(ctx context.Context) ([]physicalDisk, string, error) {
	var rows []msftPhysicalDisk
	err := wmi.QueryNamespace(
		"SELECT FriendlyName, DeviceId, MediaType, BusType, HealthStatus, Size FROM MSFT_PhysicalDisk",
		&rows, storageNS)
	if err != nil {
		return nil, "", err
	}
	rel, note := reliabilityByDisk()
	out := make([]physicalDisk, 0, len(rows))
	for _, r := range rows {
		d := physicalDisk{TempC: -1, WearPct: -1, PowerOnHours: -1}
		if c, ok := rel[r.DeviceId]; ok {
			if c.Temperature != nil {
				d.TempC = int(*c.Temperature)
			}
			if c.Wear != nil {
				d.WearPct = int(*c.Wear)
			}
			if c.PowerOnHours != nil {
				d.PowerOnHours = int64(*c.PowerOnHours)
			}
		}
		out = append(out, physicalDisk{
			TempC: d.TempC, WearPct: d.WearPct, PowerOnHours: d.PowerOnHours,
			ID:        r.DeviceId,
			Model:     r.FriendlyName,
			MediaType: mediaTypes[r.MediaType],
			BusType:   busTypes[r.BusType],
			Size:      r.Size,
			Health:    healthNames[r.HealthStatus],
		})
	}
	return out, note, nil
}
