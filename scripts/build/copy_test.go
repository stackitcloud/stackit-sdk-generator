package main

import (
	"bytes"
	"context"
	"reflect"
	"testing"
	"testing/fstest"
)

func TestRunCopy(t *testing.T) {
	fixtureFlags := []string{"--plan", "generation-plan.json"}
	fixtureGenerationPlan := []byte(`{
  "services": [
    {"service": "remain", "oas_service": "remain-oas", "action": "block"},
    {"service": "foo", "oas_service": "foo-bar", "action": "generate"},
    {"service": "obsolete", "action": "delete"},
    {"service": "bar", "oas_service": "bar-oas", "action": "block"},
    {"service": "service2", "action": "delete"}
  ]
}`)

	type args struct {
		flags          []string
		generationPlan []byte
	}
	tests := []struct {
		name    string
		args    args
		want    string
		wantErr bool
	}{
		{
			name: "success",
			args: args{
				flags:          fixtureFlags,
				generationPlan: fixtureGenerationPlan,
			},
			want:    "remain\nbar\n",
			wantErr: false,
		},
		{
			name: "no blocked services",
			args: args{
				flags: fixtureFlags,
				generationPlan: []byte(`{
  "services": [
    {"service": "remain", "oas_service": "remain-oas", "action": "generate"},
    {"service": "foo", "oas_service": "foo-bar", "action": "generate"},
    {"service": "obsolete", "action": "delete"},
    {"service": "bar", "oas_service": "bar-oas", "action": "generate"},
    {"service": "service2", "action": "delete"}
  ]
}`),
			},
			want:    "",
			wantErr: false,
		},
		{
			name: "missing flags",
			args: args{
				flags:          []string{},
				generationPlan: fixtureGenerationPlan,
			},
			want:    "",
			wantErr: true,
		},
		{
			name: "flag to invalid generationPlan",
			args: args{
				flags:          []string{"--plan", "not-existing-file.json"},
				generationPlan: fixtureGenerationPlan,
			},
			want:    "",
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			filesystem := fstest.MapFS{
				"generation-plan.json": {
					Data: tt.args.generationPlan,
				},
			}

			var stdout bytes.Buffer
			env := Environment{
				Out: &stdout,
				FS:  readOnlyFileSystem{FileSystem: filesystem},
			}

			err := runCopy(context.Background(), tt.args.flags, env)
			if (err != nil) != tt.wantErr {
				t.Errorf("runCopy() error = %v, wantErr %v", err, tt.wantErr)
			}
			if got := stdout.String(); got != tt.want {
				t.Errorf("runCopy() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestFindBlockedServices(t *testing.T) {
	type args struct {
		plan Plan
	}
	tests := []struct {
		name string
		args args
		want []string
	}{
		{
			name: "finds blocked services",
			args: args{
				plan: Plan{
					Services: []PlannedService{
						{
							Service:    "remain",
							OASService: "remain-oas",
							Action:     ActionBlock,
						},
						{
							Service: "obsolete",
							Action:  ActionDelete,
						},
						{
							Service:    "foo",
							OASService: "foo-bar",
							Action:     ActionGenerate,
						},
						{
							Service:    "bar",
							OASService: "bar-oas",
							Action:     ActionBlock,
						},
					},
				},
			},
			want: []string{"remain", "bar"},
		},
		{
			name: "no blocked services",
			args: args{
				plan: Plan{
					Services: []PlannedService{
						{
							Service:    "remain",
							OASService: "remain-oas",
							Action:     ActionGenerate,
						},
						{
							Service:    "obsolete",
							OASService: "obsolete-oas",
							Action:     ActionDelete,
						},
						{
							Service:    "foo",
							OASService: "foo-bar",
							Action:     ActionGenerate,
						},
						{
							Service:    "bar",
							OASService: "bar-oas",
							Action:     ActionDelete,
						},
					},
				},
			},
			want: nil,
		},
		{
			name: "all services are blocked",
			args: args{
				plan: Plan{
					Services: []PlannedService{
						{
							Service:    "remain",
							OASService: "remain-oas",
							Action:     ActionBlock,
						},
						{
							Service:    "obsolete",
							OASService: "remain-oas",
							Action:     ActionBlock,
						},
						{
							Service:    "foo",
							OASService: "foo-bar",
							Action:     ActionBlock,
						},
						{
							Service:    "bar",
							OASService: "bar-oas",
							Action:     ActionBlock,
						},
					},
				},
			},
			want: []string{"remain", "obsolete", "foo", "bar"},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := findBlockedServices(tt.args.plan); !reflect.DeepEqual(got, tt.want) {
				t.Errorf("findBlockedServices() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestOutputResult(t *testing.T) {
	type args struct {
		blockedServices []string
	}
	tests := []struct {
		name    string
		args    args
		want    string
		wantErr bool
	}{
		{
			name: "outputs blocked services",
			args: args{
				blockedServices: []string{
					"remain",
					"obsolete",
				},
			},
			want:    "remain\nobsolete\n",
			wantErr: false,
		},
		{
			name: "empty blocked services",
			args: args{
				blockedServices: []string{},
			},
			want:    "",
			wantErr: false,
		},
		{
			name: "nil blocked services",
			args: args{
				blockedServices: nil,
			},
			want:    "",
			wantErr: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var stdout bytes.Buffer
			env := Environment{
				Out: &stdout,
			}

			if err := outputResult(env, tt.args.blockedServices); (err != nil) != tt.wantErr {
				t.Errorf("outputResult() error = %v, wantErr %v", err, tt.wantErr)
			}

			got := stdout.String()
			if got != tt.want {
				t.Errorf("stdout = %q, want %q", got, tt.want)
			}
		})
	}
}
