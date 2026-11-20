//go:build windows

package collector

import (
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	modWlan    = windows.NewLazySystemDLL("wlanapi.dll")
	pWlanOpen  = modWlan.NewProc("WlanOpenHandle")
	pWlanClose = modWlan.NewProc("WlanCloseHandle")
	pWlanEnum  = modWlan.NewProc("WlanEnumInterfaces")
	pWlanQuery = modWlan.NewProc("WlanQueryInterface")
	pWlanFree  = modWlan.NewProc("WlanFreeMemory")
)

const (
	wlanInfoSize         = 16 + 512 + 4 // GUID + description[256] + state
	wlanOpcodeConnection = 7            // wlan_intf_opcode_current_connection
	wlanSSIDOffset       = 4 + 4 + 512  // state + mode + profile name; DOT11_SSID follows
)

// wlanSSIDs maps a Wi-Fi adapter's description to the SSID it is connected to,
// using the WLAN API (no child process, no admin). Any failure just yields an
// empty map; Windows 11 24H2+ may hide SSIDs without the location permission.
func wlanSSIDs() (out map[string]string) {
	out = map[string]string{}
	defer func() { _ = recover() }()
	if err := modWlan.Load(); err != nil {
		return out
	}
	var negotiated uint32
	var handle windows.Handle
	if r, _, _ := pWlanOpen.Call(2, 0, uintptr(unsafe.Pointer(&negotiated)), uintptr(unsafe.Pointer(&handle))); r != 0 {
		return out
	}
	defer pWlanClose.Call(uintptr(handle), 0)

	var list unsafe.Pointer
	if r, _, _ := pWlanEnum.Call(uintptr(handle), 0, uintptr(unsafe.Pointer(&list))); r != 0 || list == nil {
		return out
	}
	defer pWlanFree.Call(uintptr(list))

	n := *(*uint32)(list)
	for i := uint32(0); i < n && i < 16; i++ {
		info := unsafe.Add(list, 8+uintptr(i)*wlanInfoSize)
		desc := windows.UTF16ToString(unsafe.Slice((*uint16)(unsafe.Add(info, 16)), 256))

		var size uint32
		var data unsafe.Pointer
		var valueType uint32
		r, _, _ := pWlanQuery.Call(uintptr(handle), uintptr(info), wlanOpcodeConnection, 0,
			uintptr(unsafe.Pointer(&size)), uintptr(unsafe.Pointer(&data)), uintptr(unsafe.Pointer(&valueType)))
		if r != 0 || data == nil {
			continue
		}
		if size >= wlanSSIDOffset+4+32 {
			buf := unsafe.Slice((*byte)(data), size)
			l := *(*uint32)(unsafe.Pointer(&buf[wlanSSIDOffset]))
			if l > 0 && l <= 32 {
				out[desc] = string(buf[wlanSSIDOffset+4 : wlanSSIDOffset+4+l])
			}
		}
		pWlanFree.Call(uintptr(data))
	}
	return out
}
