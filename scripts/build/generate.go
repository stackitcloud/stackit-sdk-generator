package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io/fs"
	"strings"
)

func runGenerate(ctx context.Context, args []string, env Environment) error {
	generateFlags := flag.NewFlagSet("generate", flag.ContinueOnError)
	generateFlags.SetOutput(env.Err)

	var planPath string
	generateFlags.StringVar(&planPath, "plan", "", "path to the generation plan")
	if err := generateFlags.Parse(args); err != nil {
		return fmt.Errorf("parse generate flags: %w", err)
	}
	if len(generateFlags.Args()) != 0 {
		return fmt.Errorf("unexpected arguments: %s\n", strings.Join(generateFlags.Args(), " "))
	}
	if planPath == "" {
		return fmt.Errorf("--plan is required")
	}

	plan, err := readPlan(env.FS, planPath)
	if err != nil {
		return fmt.Errorf("read generation plan: %w\n", err)
	}

	for _, service := range plan.Services {
		if service.Action == ActionGenerate {
			// use null byte as field separator to avoid parsing/escaping issues
			fmt.Fprintf(env.Out, "%s\x00%s\n", service.OASService, service.Service)
		}
	}
	return nil
}

func readPlan(filesystem fs.FS, path string) (Plan, error) {
	contents, err := fs.ReadFile(filesystem, path)
	if err != nil {
		return Plan{}, err
	}

	var plan Plan
	if err := json.Unmarshal(contents, &plan); err != nil {
		return Plan{}, err
	}
	return plan, nil
}
