//go:build !windows

package collector

import "context"

func listAdapters(ctx context.Context) (map[string]adapterInfo, string) {
	return heuristicAdapters(ctx), "interfaces only (not Windows)"
}
