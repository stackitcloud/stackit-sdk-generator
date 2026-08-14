package main

import (
	"context"
	"flag"
	"fmt"
	"strings"
)

func runDelete(ctx context.Context, args []string, env Environment) error {
	deleteFlags := flag.NewFlagSet("delete", flag.ContinueOnError)
	deleteFlags.SetOutput(env.Err)

	var planPath string
	deleteFlags.StringVar(&planPath, "plan", "", "path to the generation plan")
	if err := deleteFlags.Parse(args); err != nil {
		return fmt.Errorf("parsing delete flags: %w", err)
	}
	if len(deleteFlags.Args()) != 0 {
		return fmt.Errorf("unexpected arguments: %s\n", strings.Join(deleteFlags.Args(), " "))
	}
	if planPath == "" {
		return fmt.Errorf("--plan is required")
	}

	plan, err := readPlan(env.FS, planPath)
	if err != nil {
		return fmt.Errorf("read generation plan: %v\n", err)
	}

	for _, service := range plan.Services {
		if service.Action == ActionDelete {
			fmt.Fprintln(env.Out, service.Service)
		}
	}
	return nil
}
