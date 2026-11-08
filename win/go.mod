module syswatch-win

go 1.22

require (
	fyne.io/systray v1.11.0
	github.com/shirou/gopsutil/v3 v3.24.5
	github.com/yusufpapurcu/wmi v1.2.4
	golang.org/x/sys v0.20.0
)

require (
	github.com/go-ole/go-ole v1.2.6 // indirect
	github.com/godbus/dbus/v5 v5.1.0 // indirect
	github.com/tklauser/go-sysconf v0.3.12 // indirect
	github.com/tklauser/numcpus v0.6.1 // indirect
)

replace fyne.io/systray => github.com/fyne-io/systray v1.11.0

replace golang.org/x/sys => github.com/golang/sys v0.20.0
