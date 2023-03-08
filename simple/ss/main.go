package main

import "github.com/matishsiao/goInfo"

func main() {
	gi, _ := goInfo.GetInfo()
	gi.VarDump()
}
