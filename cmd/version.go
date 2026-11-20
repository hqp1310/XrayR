package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var (
	version  = "0.9.6-VN (Xray-core v26)"
	codename = "XrayR"
	intro    = "Backend Xray hiệu năng cao, tối ưu RAM, Xray-core v26 - Bản Việt Hóa bởi Phương Liên 4G"
)

func init() {
	rootCmd.AddCommand(&cobra.Command{
		Use:   "version",
		Short: "Xem thông tin phiên bản XrayR",
		Run: func(cmd *cobra.Command, args []string) {
			showVersion()
		},
	})
}

func showVersion() {
	fmt.Printf("%s %s (%s) \n", codename, version, intro)
}
