package main

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

func main() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		os.Exit(1)
	}
	os.Exit(0)
}

var log *logrus.Logger

var rootCmd = &cobra.Command{
	Use:           "hello [message]",
	Short:         "Hello world example",
	SilenceUsage:  true,
	SilenceErrors: true,
	RunE:          runHello,
}

var rootOpts struct {
	verbosity string
	greeting  string
}

func init() {
	log = &logrus.Logger{
		Out:       os.Stderr,
		Formatter: new(logrus.TextFormatter),
		Hooks:     make(logrus.LevelHooks),
		Level:     logrus.WarnLevel,
	}
	rootCmd.PersistentFlags().StringVarP(&rootOpts.greeting, "greeting", "", "hello", "Greeting")
	rootCmd.PersistentFlags().StringVarP(&rootOpts.verbosity, "verbosity", "v", logrus.WarnLevel.String(), "Log level (debug, info, warn, error, fatal, panic)")
}

func runHello(cmd *cobra.Command, args []string) error {
	lvl, err := logrus.ParseLevel(rootOpts.verbosity)
	if err != nil {
		return err
	}
	log.SetLevel(lvl)
	log.WithFields(logrus.Fields{
		"time": time.Now().Format(time.RFC3339),
	}).Debug("starting hello")
	fmt.Printf("%s %s\n", rootOpts.greeting, strings.Join(args, " "))
	log.WithFields(logrus.Fields{
		"time": time.Now().Format(time.RFC3339),
	}).Debug("finished hello")
	return nil
}
