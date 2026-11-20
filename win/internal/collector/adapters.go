package collector

import (
	"context"
	"strings"

	"github.com/shirou/gopsutil/v3/net"
)

// adapterInfo is what we know about a network adapter beyond its counters.
type adapterInfo struct {
	Name        string
	Description string // driver description, e.g. "Realtek PCIe GbE Family Controller"
	Physical    bool
	Connected   bool
	SpeedBps    uint64
	Note        string // why Connected/Physical were decided (goes to the log)
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

// decideConnected combines every available signal: an adapter counts as
// connected if WMI says so in any of its fields, or if the OS interface list
// shows it up with a usable IPv4 address.
func decideConnected(status string, operStatus, mediaState uint32, hasIPv4Up bool) bool {
	return status == "Up" || operStatus == 1 || mediaState == 1 || hasIPv4Up
}

// heuristicAdapters builds adapter info from interface flags and names only;
// used on non-Windows hosts and to complement WMI.
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
		ip := ipv4Of(i)
		up := strings.Contains(flags, "up") && ip != ""
		out[i.Name] = adapterInfo{
			Name:      i.Name,
			Physical:  !looksVirtual(i.Name),
			Connected: up,
			Note:      "interfaces: flags=" + flags + " ipv4=" + ip,
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

// trimBuild turns "10.0.19045.6466 Build 19045.6466" into "10.0.19045.6466".
func trimBuild(v string) string {
	if i := strings.Index(v, " Build "); i > 0 {
		return strings.TrimSpace(v[:i])
	}
	return strings.TrimSpace(v)
}
