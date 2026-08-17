//go:build windows

package ui

import (
	"runtime"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

const (
	wmApp            = 0x8000
	wmTray           = wmApp + 1
	wmDestroy        = 0x0002
	wmCommand        = 0x0111
	wmRButtonUp      = 0x0205
	wmLButtonUp      = 0x0202
	nimAdd           = 0x00000000
	nimModify        = 0x00000001
	nimDelete        = 0x00000002
	nifMessage       = 0x00000001
	nifIcon          = 0x00000002
	nifTip           = 0x00000004
	tpmRightButton   = 0x0002
	mfString         = 0x00000000
	mfSeparator      = 0x00000800
	idiApplication   = 32512
	idConnectSOCKS   = 1001
	idConnectTUN     = 1002
	idDisconnect     = 1003
	idQuit           = 1004
)

var (
	user32   = windows.NewLazySystemDLL("user32.dll")
	shell32  = windows.NewLazySystemDLL("shell32.dll")
	kernel32 = windows.NewLazySystemDLL("kernel32.dll")

	procRegisterClassExW    = user32.NewProc("RegisterClassExW")
	procCreateWindowExW     = user32.NewProc("CreateWindowExW")
	procDefWindowProcW      = user32.NewProc("DefWindowProcW")
	procGetMessageW         = user32.NewProc("GetMessageW")
	procTranslateMessage    = user32.NewProc("TranslateMessage")
	procDispatchMessageW    = user32.NewProc("DispatchMessageW")
	procPostQuitMessage     = user32.NewProc("PostQuitMessage")
	procLoadIconW           = user32.NewProc("LoadIconW")
	procCreatePopupMenu     = user32.NewProc("CreatePopupMenu")
	procAppendMenuW         = user32.NewProc("AppendMenuW")
	procTrackPopupMenu      = user32.NewProc("TrackPopupMenu")
	procDestroyMenu         = user32.NewProc("DestroyMenu")
	procGetCursorPos        = user32.NewProc("GetCursorPos")
	procSetForegroundWindow = user32.NewProc("SetForegroundWindow")
	procShellNotifyIconW    = shell32.NewProc("Shell_NotifyIconW")
	procGetModuleHandleW    = kernel32.NewProc("GetModuleHandleW")
)

type wndClassEx struct {
	Size       uint32
	Style      uint32
	WndProc    uintptr
	ClsExtra   int32
	WndExtra   int32
	Instance   windows.Handle
	Icon       windows.Handle
	Cursor     windows.Handle
	Background windows.Handle
	MenuName   *uint16
	ClassName  *uint16
	IconSm     windows.Handle
}

type point struct{ X, Y int32 }

type msg struct {
	Hwnd    windows.Handle
	Message uint32
	WParam  uintptr
	LParam  uintptr
	Time    uint32
	Pt      point
}

type notifyIconData struct {
	Size    uint32
	Wnd     windows.Handle
	ID      uint32
	Flags   uint32
	CallbackMessage uint32
	Icon    windows.Handle
	Tip     [128]uint16
}

var (
	trayCB   Callbacks
	trayHwnd windows.Handle
	trayIcon windows.Handle
	className = syscall.StringToUTF16Ptr("TeremokHostTray")
)

func RunTray(cb Callbacks) error {
	runtime.LockOSThread()
	trayCB = cb
	hInst, _, _ := procGetModuleHandleW.Call(0)
	icon, _, _ := procLoadIconW.Call(0, uintptr(idiApplication))
	trayIcon = windows.Handle(icon)

	wc := wndClassEx{
		Size:      uint32(unsafe.Sizeof(wndClassEx{})),
		WndProc:   syscall.NewCallback(wndProc),
		Instance:  windows.Handle(hInst),
		ClassName: className,
		Icon:      trayIcon,
	}
	if atom, _, err := procRegisterClassExW.Call(uintptr(unsafe.Pointer(&wc))); atom == 0 {
		return err
	}
	const (
		wsPopup        = 0x80000000
		wsExToolwindow = 0x00000080
	)
	title, _ := syscall.UTF16PtrFromString("TeremokHost")
	hwnd, _, err := procCreateWindowExW.Call(
		wsExToolwindow,
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(title)),
		wsPopup,
		0, 0, 0, 0,
		0,
		0,
		hInst,
		0,
	)
	if hwnd == 0 {
		return err
	}
	trayHwnd = windows.Handle(hwnd)
	if err := notify(nimAdd, "Teremok Connect"); err != nil {
		return err
	}
	var m msg
	for {
		ret, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0)
		if int32(ret) <= 0 {
			break
		}
		procTranslateMessage.Call(uintptr(unsafe.Pointer(&m)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&m)))
	}
	_ = notify(nimDelete, "")
	return nil
}

func SetTip(text string) {
	if trayHwnd == 0 {
		return
	}
	_ = notify(nimModify, text)
}

func notify(action uint32, tip string) error {
	var nid notifyIconData
	nid.Size = uint32(unsafe.Sizeof(nid))
	nid.Wnd = trayHwnd
	nid.ID = 1
	nid.Flags = nifMessage | nifIcon | nifTip
	nid.CallbackMessage = wmTray
	nid.Icon = trayIcon
	copyUTF16(nid.Tip[:], tip)
	r, _, err := procShellNotifyIconW.Call(uintptr(action), uintptr(unsafe.Pointer(&nid)))
	if r == 0 {
		return err
	}
	return nil
}

func copyUTF16(dst []uint16, s string) {
	u, _ := syscall.UTF16FromString(s)
	if len(u) > len(dst) {
		u = u[:len(dst)]
		u[len(dst)-1] = 0
	}
	copy(dst, u)
}

func wndProc(hwnd, msg, wparam, lparam uintptr) uintptr {
	switch msg {
	case wmTray:
		if lparam == wmRButtonUp || lparam == wmLButtonUp {
			showMenu(windows.Handle(hwnd))
		}
	case wmCommand:
		switch uint16(wparam) {
		case idConnectSOCKS:
			if trayCB.OnConnectSOCKS != nil {
				go trayCB.OnConnectSOCKS()
			}
		case idConnectTUN:
			if trayCB.OnConnectTUN != nil {
				go trayCB.OnConnectTUN()
			}
		case idDisconnect:
			if trayCB.OnDisconnect != nil {
				go trayCB.OnDisconnect()
			}
		case idQuit:
			if trayCB.OnQuit != nil {
				trayCB.OnQuit()
			}
			procPostQuitMessage.Call(0)
		}
	case wmDestroy:
		procPostQuitMessage.Call(0)
	default:
		r, _, _ := procDefWindowProcW.Call(hwnd, msg, wparam, lparam)
		return r
	}
	return 0
}

func showMenu(hwnd windows.Handle) {
	menu, _, _ := procCreatePopupMenu.Call()
	appendItem(menu, idConnectSOCKS, "Connect (SOCKS, no admin)")
	appendItem(menu, idConnectTUN, "Connect (TUN, UAC)")
	procAppendMenuW.Call(menu, mfSeparator, 0, 0)
	appendItem(menu, idDisconnect, "Disconnect")
	appendItem(menu, idQuit, "Quit")
	var pt point
	procGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))
	procSetForegroundWindow.Call(uintptr(hwnd))
	procTrackPopupMenu.Call(menu, tpmRightButton, uintptr(pt.X), uintptr(pt.Y), 0, uintptr(hwnd), 0)
	procDestroyMenu.Call(menu)
}

func appendItem(menu uintptr, id uint16, title string) {
	p, _ := syscall.UTF16PtrFromString(title)
	procAppendMenuW.Call(menu, mfString, uintptr(id), uintptr(unsafe.Pointer(p)))
}
