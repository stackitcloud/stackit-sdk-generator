package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io/fs"
	"sort"
	"strings"
)

type PlanParams struct {
	SpecDir         string
	ServiceDir      string
	BlocklistPath   string
	OutputPath      string
	IncludedService map[string]struct{}
}

type Plan struct {
	Services []PlannedService `json:"services"`
}

type Action string

const (
	ActionGenerate    Action = "generate"
	ActionBlock       Action = "block"
	ActionDelete      Action = "delete"
	ActionNotIncluded Action = "not_included"
)

type PlannedService struct {
	Service    string `json:"service"`
	OASService string `json:"oas_service,omitempty"`
	Action     Action `json:"action"`
}

func runPlan(ctx context.Context, global Global, language Language, args []string, env Environment) error {
	planFlags := flag.NewFlagSet("plan", flag.ContinueOnError)
	planFlags.SetOutput(env.Err)

	var params PlanParams
	var includedServices []string
	planFlags.StringVar(&params.SpecDir, "spec-dir", "", "directory containing OAS service directories")
	planFlags.StringVar(&params.ServiceDir, "service-dir", "", "directory containing generated service directories")
	planFlags.StringVar(&params.BlocklistPath, "blocklist", "", "path to the language blocklist")
	planFlags.StringVar(&params.OutputPath, "output", "", "path to write the JSON plan")
	planFlags.Func("include-service", "service eligible for generation (may be repeated)", func(service string) error {
		includedServices = append(includedServices, service)
		return nil
	})
	if err := planFlags.Parse(args); err != nil {
		return fmt.Errorf("parsing plan flages: %w", err)
	}
	if len(planFlags.Args()) != 0 {
		return fmt.Errorf("unexpected arguments: %s", strings.Join(planFlags.Args(), " "))
	}
	params.IncludedService = make(map[string]struct{}, len(includedServices))
	for _, service := range includedServices {
		params.IncludedService[service] = struct{}{}
	}

	if err := validatePlanParams(params); err != nil {
		return fmt.Errorf("invalid plan arguments: %w\n", err)
	}

	plan, err := createPlan(env.FS, params, language)
	if err != nil {
		return fmt.Errorf("create plan: %w\n", err)
	}
	var formatted []byte
	if formatted, err = formatPlan(plan); err != nil {
		return fmt.Errorf("format plan: %w\n", err)
	}
	if _, err = env.Out.Write(formatted); err != nil {
		return fmt.Errorf("print plan: %w\n", err)
	}
	if err = env.FS.WriteFile(params.OutputPath, formatted, 0o644); err != nil {
		return fmt.Errorf("write plan: %w\n", err)
	}

	if global.Verbose {
		fmt.Fprintf(env.Err, "wrote plan for %d services to %s\n", len(plan.Services), params.OutputPath)
	}
	return nil
}

func validatePlanParams(params PlanParams) error {
	for name, value := range map[string]string{
		"spec-dir":    params.SpecDir,
		"service-dir": params.ServiceDir,
		"blocklist":   params.BlocklistPath,
		"output":      params.OutputPath,
	} {
		if value == "" {
			return fmt.Errorf("--%s is required", name)
		}
	}
	return nil
}

func createPlan(filesystem FileSystem, params PlanParams, language Language) (Plan, error) {
	blocked, err := readBlocklist(filesystem, params.BlocklistPath)
	if err != nil {
		return Plan{}, err
	}

	specEntries, err := fs.ReadDir(filesystem, params.SpecDir)
	if err != nil {
		return Plan{}, fmt.Errorf("read spec directory: %w", err)
	}
	services := make(map[string]PlannedService, len(specEntries))
	for _, entry := range specEntries {
		if !entry.IsDir() {
			continue
		}

		oasService := entry.Name()
		service := language.NormalizeServiceName(oasService)
		if service == "" {
			return Plan{}, fmt.Errorf("OAS service %q has no valid service name", oasService)
		}
		if previous, exists := services[service]; exists {
			return Plan{}, fmt.Errorf("OAS services %q and %q both normalize to %q", previous.OASService, oasService, service)
		}

		action := ActionGenerate
		if _, isBlocked := blocked[service]; isBlocked {
			action = ActionBlock
		} else if len(params.IncludedService) > 0 && !isIncluded(params.IncludedService, service) {
			action = ActionNotIncluded
		}
		services[service] = PlannedService{Service: service, OASService: oasService, Action: action}
	}

	serviceEntries, err := fs.ReadDir(filesystem, params.ServiceDir)
	if err != nil {
		return Plan{}, fmt.Errorf("read service directory: %w", err)
	}
	for _, entry := range serviceEntries {
		if !entry.IsDir() {
			continue
		}
		service := entry.Name()
		if _, exists := services[service]; !exists {
			services[service] = PlannedService{Service: service, Action: ActionDelete}
		}
	}

	plan := Plan{Services: make([]PlannedService, 0, len(services))}
	for _, service := range services {
		plan.Services = append(plan.Services, service)
	}
	sort.Slice(plan.Services, func(i, j int) bool {
		return plan.Services[i].Service < plan.Services[j].Service
	})
	return plan, nil
}

func readBlocklist(filesystem FileSystem, path string) (map[string]struct{}, error) {
	contents, err := fs.ReadFile(filesystem, path)
	if err != nil {
		return nil, err
	}

	blocked := make(map[string]struct{})
	for line := range strings.SplitSeq(string(contents), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		blocked[line] = struct{}{}
	}
	return blocked, nil
}

func isIncluded(included map[string]struct{}, service string) bool {
	_, ok := included[service]
	return ok
}

func formatPlan(plan Plan) ([]byte, error) {
	contents, err := json.MarshalIndent(plan, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(contents, '\n'), nil
}
