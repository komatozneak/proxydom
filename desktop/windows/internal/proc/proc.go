package proc

// Handle is a running hysteria.exe (same-user) or an elevated TUN child.
type Handle interface {
	Stop() error
}

// StartOpts locate official binaries next to the host (or in -bin-dir).
type StartOpts struct {
	HysteriaPath string
	ConfigPath   string
	WorkDir      string
	Elevated     bool
}

// Starter launches hysteria. Windows implements real spawn; other OS stub.
type Starter interface {
	Start(opts StartOpts) (Handle, error)
}
