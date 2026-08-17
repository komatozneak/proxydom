//go:build !windows

package proc

import "fmt"

type stubStarter struct{}

func NewStarter() Starter { return stubStarter{} }

func (stubStarter) Start(StartOpts) (Handle, error) {
	return nil, fmt.Errorf("hysteria spawn is Windows-only")
}
