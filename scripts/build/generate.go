package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io/fs"
	"strings"
)

func runGenerate(ctx context.Context, args []string, io IO) bool {
	generateFlags := flag.NewFlagSet("generate", flag.ContinueOnError)
	generateFlags.SetOutput(io.Err)

	var planPath string
	generateFlags.StringVar(&planPath, "plan", "", "path to the generation plan")
	if err := generateFlags.Parse(args); err != nil {
		return false
	}
	if len(generateFlags.Args()) != 0 {
		fmt.Fprintf(io.Err, "unexpected arguments: %s\n", strings.Join(generateFlags.Args(), " "))
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
		if service.Action == "generate" {
			// use null byte as field separator to avoid parsing/escaping issues
			fmt.Fprintf(io.Out, "%s\x00%s\n", service.OASService, service.Service)
		}
	}
	return true
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
