package ui

// Callbacks are tray menu actions. Headless mode never calls RunTray.
type Callbacks struct {
	OnConnectSOCKS func()
	OnConnectTUN   func()
	OnDisconnect   func()
	OnQuit         func()
}
