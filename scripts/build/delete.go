package main

import (
	"context"
	"flag"
	"fmt"
	"strings"
)

func runDelete(ctx context.Context, args []string, io IO) bool {
	deleteFlags := flag.NewFlagSet("delete", flag.ContinueOnError)
	deleteFlags.SetOutput(io.Err)

	var planPath string
	deleteFlags.StringVar(&planPath, "plan", "", "path to the generation plan")
	if err := deleteFlags.Parse(args); err != nil {
		return false
	}
	if len(deleteFlags.Args()) != 0 {
		fmt.Fprintf(io.Err, "unexpected arguments: %s\n", strings.Join(deleteFlags.Args(), " "))
		return false
	}
	if planPath == "" {
		fmt.Fprintln(io.Err, "--plan is required")
		return false
	}

	plan, err := readPlan(io.FS, planPath)
	if err != nil {
		fmt.Fprintf(io.Err, "read generation plan: %v\n", err)
		return false
	}

	for _, service := range plan.Services {
		if service.Action == "delete" {
			fmt.Fprintln(io.Out, service.Service)
		}
	}
	return true
}
