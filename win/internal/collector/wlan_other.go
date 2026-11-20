//go:build !windows

package collector

// wlanSSIDs has no source off Windows.
func wlanSSIDs() map[string]string { return map[string]string{} }
