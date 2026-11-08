// Package tray shows the notification-area icon and menu.
package tray

import (
	"fmt"
	"time"

	"fyne.io/systray"

	"syswatch-win/internal/app"
	"syswatch-win/internal/config"
	"syswatch-win/internal/platform"
)

var icons struct{ green, amber, gray, red []byte }

// Run blocks until the user quits. onQuit runs once before returning.
func Run(a *app.App, version string, onQuit func()) {
	icons.green, icons.amber = makeICO(colGreen), makeICO(colAmber)
	icons.gray, icons.red = makeICO(colGray), makeICO(colRed)
	systray.Run(func() { onReady(a, version) }, onQuit)
}

func onReady(a *app.App, version string) {
	t := func(s string) string { return a.Translator().T(s) }
	systray.SetIcon(icons.gray)
	systray.SetTitle("SysWatch")
	systray.SetTooltip("SysWatch " + version)

	mStatus := systray.AddMenuItem("SysWatch "+version, "")
	mStatus.Disable()
	systray.AddSeparator()
	mFolder := systray.AddMenuItem(t("Open output folder"), "")
	mSettings := systray.AddMenuItem(t("Open settings"), "")
	mReload := systray.AddMenuItem(t("Reload settings"), "")
	mPause := systray.AddMenuItem(t("Pause"), "")
	var mAuto *systray.MenuItem
	if platform.Autostart() {
		mAuto = systray.AddMenuItemCheckbox(t("Start with Windows"), "", true)
	} else {
		mAuto = systray.AddMenuItemCheckbox(t("Start with Windows"), "", false)
	}
	systray.AddSeparator()
	mQuit := systray.AddMenuItem(t("Quit"), "")

	refresh := func() {
		s := a.Status()
		var icon []byte
		var text string
		switch {
		case s.ConfigErr != "":
			icon, text = icons.red, "settings.json: "+s.ConfigErr
		case !s.Configured:
			icon, text = icons.amber, t("Output folder not configured")
		case s.Paused:
			icon, text = icons.gray, t("Paused")
		case s.NotReady:
			icon, text = icons.amber, t("Output folder not available (.import missing)")
		default:
			icon = icons.green
			text = t("Writing")
			if !s.LastWrite.IsZero() {
				text += " · " + s.LastWrite.Format("15:04:05")
			}
		}
		systray.SetIcon(icon)
		systray.SetTooltip("SysWatch · " + text)
		mStatus.SetTitle(text)
		mFolder.SetTitle(t("Open output folder"))
		mSettings.SetTitle(t("Open settings"))
		mReload.SetTitle(t("Reload settings"))
		mAuto.SetTitle(t("Start with Windows"))
		mQuit.SetTitle(t("Quit"))
		if s.Paused {
			mPause.SetTitle(t("Resume"))
		} else {
			mPause.SetTitle(t("Pause"))
		}
	}
	refresh()

	go func() {
		tick := time.NewTicker(2 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-tick.C:
				refresh()
			case <-mFolder.ClickedCh:
				if dir := a.Config().OutputDir; dir != "" {
					_ = platform.Open(dir)
				}
			case <-mSettings.ClickedCh:
				_ = platform.Open(a.ConfigPath())
			case <-mReload.ClickedCh:
				_ = a.Reload()
				refresh()
			case <-mPause.ClickedCh:
				a.SetPaused(!a.Paused())
				refresh()
			case <-mAuto.ClickedCh:
				enable := !mAuto.Checked()
				if err := platform.SetAutostart(enable, platform.Exe()); err == nil {
					if enable {
						mAuto.Check()
					} else {
						mAuto.Uncheck()
					}
					persistAutostart(a, enable)
				}
			case <-mQuit.ClickedCh:
				systray.Quit()
				return
			}
		}
	}()
}

// persistAutostart keeps config.json in sync with the menu toggle.
func persistAutostart(a *app.App, enable bool) {
	cfg := a.Config()
	if cfg == nil || cfg.Autostart == enable {
		return
	}
	c := *cfg
	c.Autostart = enable
	if err := config.Save(a.ConfigPath(), &c); err != nil {
		fmt.Println("cannot save autostart:", err)
	}
}
