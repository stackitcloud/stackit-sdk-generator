package main

import (
	"bytes"
	"context"
	"testing"
	"testing/fstest"
)

func TestRunDeletePrintsServicesMarkedForDeletion(t *testing.T) {
	filesystem := fstest.MapFS{
		"generation-plan.json": {Data: []byte(`{
  "services": [
    {"service": "blocked", "oas_service": "blocked", "action": "block"},
    {"service": "foo", "oas_service": "foo-bar", "action": "generate"},
    {"service": "obsolete", "action": "delete"},
    {"service": "service2", "action": "delete"}
  ]
}`)},
	}
	var stdout, stderr bytes.Buffer

	err := runDelete(context.Background(), []string{"--plan", "generation-plan.json"}, Environment{
		Out: &stdout,
		Err: &stderr,
		FS:  readOnlyFileSystem{FileSystem: filesystem},
	})
	if err != nil {
		t.Fatalf("runDelete failed: %v", err)
	}
	if got, want := stdout.String(), "obsolete\nservice2\n"; got != want {
		t.Errorf("stdout = %q, want %q", got, want)
	}
}
