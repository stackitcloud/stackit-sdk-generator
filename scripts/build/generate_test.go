package main

import (
	"bytes"
	"context"
	"io/fs"
	"testing"
	"testing/fstest"
)

func TestRunGeneratePrintsServicesMarkedForGeneration(t *testing.T) {
	filesystem := fstest.MapFS{
		"generation-plan.json": {Data: []byte(`{
  "services": [
    {"service": "blocked", "oas_service": "blocked", "action": "block"},
    {"service": "foo", "oas_service": "foo-bar", "action": "generate"},
    {"service": "obsolete", "action": "delete"},
    {"service": "service2", "oas_service": "service-2", "action": "generate"}
  ]
}`)},
	}
	var stdout, stderr bytes.Buffer

	ok := runGenerate(context.Background(), []string{"--plan", "generation-plan.json"}, IO{
		Out: &stdout,
		Err: &stderr,
		FS:  readOnlyFileSystem{FileSystem: filesystem},
	})
	if !ok {
		t.Fatalf("runGenerate returned false: %s", stderr.String())
	}
	if got, want := stdout.String(), "foo-bar\x00foo\nservice-2\x00service2\n"; got != want {
		t.Errorf("stdout = %q, want %q", got, want)
	}
}

type readOnlyFileSystem struct {
	FileSystem fstest.MapFS
}

func (filesystem readOnlyFileSystem) Open(name string) (fs.File, error) {
	return filesystem.FileSystem.Open(name)
}

func (filesystem readOnlyFileSystem) WriteFile(string, []byte, fs.FileMode) error {
	return nil
}
