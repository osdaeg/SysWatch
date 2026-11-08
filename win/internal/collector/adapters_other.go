//go:build !windows

package collector

import "context"

func listAdapters(ctx context.Context) map[string]adapterInfo { return heuristicAdapters(ctx) }
