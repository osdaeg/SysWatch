//go:build !windows

package collector

import "context"

// listPhysicalDisks has no portable source off Windows; no disks, no states.
func listPhysicalDisks(ctx context.Context) ([]physicalDisk, string, error) {
	return nil, "not Windows", nil
}
