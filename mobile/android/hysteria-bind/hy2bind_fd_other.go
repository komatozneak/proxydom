//go:build !unix

package hy2bind

func closeTunFd(fd int) {}
