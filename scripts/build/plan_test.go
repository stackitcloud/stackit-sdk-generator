package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io/fs"
	"reflect"
	"testing"
	"testing/fstest"
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
		"languages/go/blocklist.txt":           {Data: []byte("# blocked services\nblocked\n")},
	}, writes: make(map[string][]byte)}
	var stdout, stderr bytes.Buffer

	ok := runPlan(context.Background(), Global{Language: "go"}, goLanguage{}, []string{
		"--spec-dir", "oas/services",
		"--service-dir", "services",
		"--blocklist", "languages/go/blocklist.txt",
		"--output", outputPath,
	}, IO{Out: &stdout, Err: &stderr, FS: filesystem})
	if !ok {
		t.Fatalf("runPlan returned false: %s", stderr.String())
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
		{Service: "blocked", OASService: "blocked", Action: "block"},
		{Service: "foobar", OASService: "foo-bar", Action: "generate"},
		{Service: "obsolete", Action: "delete"},
	}
	if !reflect.DeepEqual(plan.Services, want) {
		t.Errorf("services = %#v, want %#v", plan.Services, want)
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

	ok := runPlan(context.Background(), Global{Language: "go"}, goLanguage{}, []string{
		"--spec-dir", "oas/services",
		"--service-dir", "services",
		"--blocklist", "languages/go/blocklist.txt",
		"--output", outputPath,
		"--include-service", "alice",
		"--include-service", "bob",
	}, IO{Out: &stdout, Err: &stderr, FS: filesystem})
	if !ok {
		t.Fatalf("runPlan returned false: %s", stderr.String())
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
		{Service: "alice", OASService: "alice", Action: "generate"},
		{Service: "bob", OASService: "bob", Action: "block"},
		{Service: "charlie", OASService: "charlie", Action: "not_included"},
	}
	if !reflect.DeepEqual(plan.Services, want) {
		t.Errorf("services = %#v, want %#v", plan.Services, want)
	}
}
