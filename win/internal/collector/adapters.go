package collector

import (
	"context"
	"strings"

	"github.com/shirou/gopsutil/v3/net"
)

// adapterInfo is what we know about a network adapter beyond its counters.
type adapterInfo struct {
	Name      string
	Physical  bool
	Connected bool
	SpeedBps  uint64
}

var virtualHints = []string{
	"vethernet", "hyper-v", "vmware", "virtualbox", "vbox", "loopback", "isatap", "teredo",
	"wsl", "docker", "veth", "virbr", "br-", "tun", "tap", "tailscale", "zerotier", "wireguard",
	"openvpn", "bluetooth", "pseudo",
}

func looksVirtual(name string) bool {
	l := strings.ToLower(name)
	for _, h := range virtualHints {
		if strings.Contains(l, h) {
			return true
		}
	}
	return false
}

// heuristicAdapters builds adapter info from interface flags and names only;
// used on non-Windows hosts and as a fallback when WMI is unavailable.
func heuristicAdapters(ctx context.Context) map[string]adapterInfo {
	out := map[string]adapterInfo{}
	ifs, err := net.InterfacesWithContext(ctx)
	if err != nil {
		return out
	}
	for _, i := range ifs {
		flags := strings.Join(i.Flags, ",")
		if strings.Contains(flags, "loopback") {
			continue
		}
		out[i.Name] = adapterInfo{
			Name:      i.Name,
			Physical:  !looksVirtual(i.Name),
			Connected: strings.Contains(flags, "up") && ipv4Of(i) != "",
		}
	}
	return out
}

// ipv4Of returns the first routable IPv4 address of an interface.
func ipv4Of(i net.InterfaceStat) string {
	for _, a := range i.Addrs {
		addr := a.Addr
		if k := strings.IndexByte(addr, '/'); k > 0 {
			addr = addr[:k]
		}
		if strings.Count(addr, ".") == 3 && !strings.HasPrefix(addr, "169.254.") && !strings.HasPrefix(addr, "127.") {
			return addr
		}
	}
	return ""
}
