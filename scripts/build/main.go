package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	ctx := context.Background()
	ctx, stop := signal.NotifyContext(ctx, syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	workingDirectory, err := os.Getwd()
	if err != nil {
		panic(err)
	}
	root, err := os.OpenRoot(workingDirectory)
	if err != nil {
		panic(err)
	}
	defer root.Close()

	env := Environment{
		Args: os.Args[1:],
		In:   os.Stdin,
		Out:  os.Stdout,
		Err:  os.Stderr,
		FS:   rootFileSystem{root: root},
	}

	if ok := run(ctx, env); !ok {
		os.Exit(1)
	}
}

type FileSystem interface {
	fs.FS
	WriteFile(name string, data []byte, perm fs.FileMode) error
}

type rootFileSystem struct {
	root *os.Root
}

func (filesystem rootFileSystem) Open(name string) (fs.File, error) {
	return filesystem.root.Open(name)
}

func (filesystem rootFileSystem) WriteFile(name string, data []byte, perm fs.FileMode) error {
	file, err := filesystem.root.OpenFile(name, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, perm)
	if err != nil {
		return err
	}
	written, writeErr := file.Write(data)
	closeErr := file.Close()
	if writeErr != nil {
		return writeErr
	}
	if written != len(data) {
		return io.ErrShortWrite
	}
	return closeErr
}

type Environment struct {
	Args []string
	In   io.Reader
	Out  io.Writer
	Err  io.Writer
	FS   FileSystem
}

type Global struct {
	Verbose  bool
	Language string
}

func run(ctx context.Context, env Environment) bool {
	var global Global
	globalF := flag.NewFlagSet("build", flag.ContinueOnError)
	globalF.SetOutput(env.Err)
	globalF.BoolVar(&global.Verbose, "verbose", false, "enable verbose output")
	globalF.StringVar(&global.Language, "language", "go", "the programming language to use (go, python, java)")
	if err := globalF.Parse(env.Args); err != nil {
		fmt.Fprintf(env.Err, "error parsing global flags: %v\n", err)
		return false
	}

	args := globalF.Args()
	if len(args) == 0 {
		fmt.Fprintln(env.Err, "expected a command")
		return false
	}

	language, err := newLanguage(global.Language)
	if err != nil {
		fmt.Fprintln(env.Err, err)
		return false
	}

	switch args[0] {
	case "plan":
		err = runPlan(ctx, global, language, args[1:], env)
	case "generate":
		err = runGenerate(ctx, args[1:], env)
	case "delete":
		err = runDelete(ctx, args[1:], env)
	default:
		fmt.Fprintf(env.Err, "unknown command %q\n", args[0])
		return false
	}

	if err != nil {
		fmt.Fprintf(env.Err, "running %s: %v", args[0], err)
		return false
	}
	return true
}
