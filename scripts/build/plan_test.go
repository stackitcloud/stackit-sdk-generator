package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io/fs"
	"testing"
	"testing/fstest"

	"github.com/google/go-cmp/cmp"
)

type mapFileSystem struct {
	files  fstest.MapFS
	writes map[string][]byte
}

func (filesystem *mapFileSystem) Open(name string) (fs.File, error) {
	return filesystem.files.Open(name)
}

func (filesystem *mapFileSystem) WriteFile(name string, data []byte, _ fs.FileMode) error {
	filesystem.writes[name] = append([]byte(nil), data...)
	return nil
}

func TestRunPlan(t *testing.T) {
	const outputPath = "generation-plan.json"
	filesystem := &mapFileSystem{files: fstest.MapFS{
		"oas/services/blocked/v1/blocked.json": {Data: []byte{}},
		"oas/services/foo-bar/v1/foo-bar.json": {Data: []byte{}},
		"services/foobar/.keep":                {Data: []byte{}},
		"services/obsolete/.keep":              {Data: []byte{}},
		"services/deleteblocked/.keep":         {Data: []byte{}},
		"languages/go/blocklist.txt":           {Data: []byte("# blocked services\nblocked\ndeleteblocked")},
	}, writes: make(map[string][]byte)}
	var stdout, stderr bytes.Buffer

	err := runPlan(context.Background(), Global{Language: "go"}, goLanguage{}, []string{
		"--spec-dir", "oas/services",
		"--service-dir", "services",
		"--blocklist", "languages/go/blocklist.txt",
		"--output", outputPath,
	}, Environment{Out: &stdout, Err: &stderr, FS: filesystem})
	if err != nil {
		t.Fatalf("runPlan failed: %v", err)
	}

	contents, ok := filesystem.writes[outputPath]
	if !ok {
		t.Fatalf("plan was not written to %q", outputPath)
	}
	var plan Plan
	if err := json.Unmarshal(contents, &plan); err != nil {
		t.Fatal(err)
	}
	if got, want := stdout.String(), string(contents); got != want {
		t.Errorf("stdout = %q, want %q", got, want)
	}
	want := []PlannedService{
		{Service: "blocked", OASService: "blocked", Action: ActionBlock},
		{Service: "deleteblocked", Action: ActionDelete},
		{Service: "foobar", OASService: "foo-bar", Action: ActionGenerate},
		{Service: "obsolete", Action: ActionDelete},
	}
	if diff := cmp.Diff(want, plan.Services); diff != "" {
		t.Errorf("services mismatch (-want +got):\n%s", diff)
	}
}

func TestRunPlanIncludeService(t *testing.T) {
	const outputPath = "generation-plan.json"
	filesystem := &mapFileSystem{
		files: fstest.MapFS{
			"oas/services/alice/v1/alice.json":     {Data: []byte{}},
			"oas/services/bob/v1/bob.json":         {Data: []byte{}},
			"oas/services/charlie/v1/charlie.json": {Data: []byte{}},
			"services/.keep":                       {Data: []byte{}},
			"languages/go/blocklist.txt": {Data: []byte(`
				bob`,
			)},
		},
		writes: make(map[string][]byte),
	}
	var stdout, stderr bytes.Buffer

	err := runPlan(context.Background(), Global{Language: "go"}, goLanguage{}, []string{
		"--spec-dir", "oas/services",
		"--service-dir", "services",
		"--blocklist", "languages/go/blocklist.txt",
		"--output", outputPath,
		"--include-service", "alice",
		"--include-service", "bob",
	}, Environment{Out: &stdout, Err: &stderr, FS: filesystem})
	if err != nil {
		t.Fatalf("runPlan failed: %v", err)
	}

	contents, ok := filesystem.writes[outputPath]
	if !ok {
		t.Fatalf("plan was not written to %q", outputPath)
	}
	var plan Plan
	if err := json.Unmarshal(contents, &plan); err != nil {
		t.Fatal(err)
	}
	if got, want := stdout.String(), string(contents); got != want {
		t.Errorf("stdout = %q, want %q", got, want)
	}
	want := []PlannedService{
		{Service: "alice", OASService: "alice", Action: ActionGenerate},
		{Service: "bob", OASService: "bob", Action: ActionBlock},
		{Service: "charlie", OASService: "charlie", Action: ActionNotIncluded},
	}
	if diff := cmp.Diff(want, plan.Services); diff != "" {
		t.Errorf("services mismatch (-want +got):\n%s", diff)
	}
}
