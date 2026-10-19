package main

import (
	"context"
	"flag"
	"fmt"
	"strings"
)

func runCopy(_ context.Context, args []string, env Environment) error {
	copyFlags := flag.NewFlagSet("copy", flag.ContinueOnError)
	copyFlags.SetOutput(env.Err)

	var planPath string
	copyFlags.StringVar(&planPath, "plan", "", "path to the generation plan")
	if err := copyFlags.Parse(args); err != nil {
		return fmt.Errorf("parsing copy flags: %w", err)
	}
	if len(copyFlags.Args()) != 0 {
		return fmt.Errorf("unexpected arguments: %s", strings.Join(copyFlags.Args(), " "))
	}
	if planPath == "" {
		return fmt.Errorf("--plan is required")
	}

	plan, err := readPlan(env.FS, planPath)
	if err != nil {
		return fmt.Errorf("read generation plan: %w", err)
	}

	for _, service := range plan.Services {
		if service.Action == ActionBlock {
			fmt.Fprintln(env.Out, service.Service)
		}
	}
	return nil
}
