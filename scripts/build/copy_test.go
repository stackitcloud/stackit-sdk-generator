package main

import (
	"bytes"
	"context"
	"testing"
	"testing/fstest"
)

func TestRunCopyPrintsServicesMarkedOnBlocklist(t *testing.T) {
	filesystem := fstest.MapFS{
		"generation-plan.json": {
			Data: []byte(`{
  "services": [
    {"service": "remain", "oas_service": "remain_oas", "action": "block"},
    {"service": "foo", "oas_service": "foo-bar", "action": "generate"},
    {"service": "obsolete", "action": "delete"},
    {"service": "bar", "oas_service": "bar_oas", "action": "block"},
    {"service": "service2", "action": "delete"}
  ]
}`),
		},
	}
	var stdout, stderr bytes.Buffer

	err := runCopy(context.Background(), []string{"--plan", "generation-plan.json"}, Environment{
		Out: &stdout,
		Err: &stderr,
		FS:  readOnlyFileSystem{FileSystem: filesystem},
	})
	if err != nil {
		t.Fatalf("runCopy failed: %v", err)
	}
	if got, want := stdout.String(), "remain\nbar\n"; got != want {
		t.Errorf("stdout = %q, want %q", got, want)
	}
}
