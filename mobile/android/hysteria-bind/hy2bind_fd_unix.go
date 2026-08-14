//go:build unix

package hy2bind

import "golang.org/x/sys/unix"

func closeTunFd(fd int) {
	_ = unix.Close(fd)
}
