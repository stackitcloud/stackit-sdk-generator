package main

import (
	"context"
	"flag"
	"fmt"
	"strings"
)

// runCopy implements the `copy --plan <path/to/generation-plan.json>` command.
// It prints all services which have the action "block" in the generation-plan. These services should be copied
// during the generation, to prevent that they will be removed.
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

	blockedServices := findBlockedServices(plan)

	return outputResult(env, blockedServices)
}

// findBlockedServices finds all services in `Plan.Service` which are blocked and returns the service name in a string slice.
func findBlockedServices(plan Plan) []string {
	var blockedServices []string
	for _, service := range plan.Services {
		if service.Action == ActionBlock {
			blockedServices = append(blockedServices, service.Service)
		}
	}

	return blockedServices
}

// outputResult takes a list of blockedServices and writes service in a separate line into `env.Out`.
func outputResult(env Environment, blockedServices []string) error {
	if len(blockedServices) == 0 {
		return nil
	}

	result := fmt.Sprintf("%s\n", strings.Join(blockedServices, "\n"))

	_, err := fmt.Fprint(env.Out, result)
	if err != nil {
		return fmt.Errorf("writing result: %w", err)
	}

	return nil
}
