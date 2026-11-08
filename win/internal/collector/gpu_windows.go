//go:build windows

package collector

import (
	"fmt"
	"strings"

	"golang.org/x/sys/windows/registry"
)

const displayClass = `SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}`

// gpuInfo lists display adapters from the registry (readable without admin).
// WMI's AdapterRAM is capped at 4 GB, so memory comes from qwMemorySize.
func gpuInfo() string {
	root, err := registry.OpenKey(registry.LOCAL_MACHINE, displayClass, registry.ENUMERATE_SUB_KEYS)
	if err != nil {
		return ""
	}
	defer root.Close()
	subs, err := root.ReadSubKeyNames(-1)
	if err != nil {
		return ""
	}
	var names []string
	for _, sub := range subs {
		if len(sub) != 4 || strings.Trim(sub, "0123456789") != "" {
			continue
		}
		k, err := registry.OpenKey(registry.LOCAL_MACHINE, displayClass+`\`+sub, registry.QUERY_VALUE)
		if err != nil {
			continue
		}
		desc, _, err := k.GetStringValue("DriverDesc")
		if err != nil || desc == "" {
			k.Close()
			continue
		}
		label := desc
		if mem, _, err := k.GetIntegerValue("HardwareInformation.qwMemorySize"); err == nil && mem > 0 {
			if gb := float64(mem) / (1 << 30); gb >= 1 {
				label = fmt.Sprintf("%s (%.0f GB)", desc, gb)
			} else {
				label = fmt.Sprintf("%s (%d MB)", desc, mem>>20)
			}
		}
		k.Close()
		names = append(names, label)
	}
	return strings.Join(names, ", ")
}
