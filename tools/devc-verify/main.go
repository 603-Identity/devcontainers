// Command devc-verify is the gate's verification tool for consumers of the shared
// devcontainer images. See README.md for the CLI contract and exit codes.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/attest"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/bump"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/consumer"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/image"
)

// Exit codes. Only exitFalse means "the predicate is false"; every other non-zero code is
// an error, so an infrastructure fault can never be read as a plain "no".
const (
	exitOK    = 0
	exitError = 2
	exitFalse = 3
)

const (
	usage        = "usage: devc-verify files|attest|verify|decide [flags]"
	maxPatchSize = 4 << 20
	attestBudget = 8 * time.Minute
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr, attest.ExecRunner{}))
}

// run executes one subcommand and returns the process exit code.
func run(args []string, stdout, stderr io.Writer, runner attest.Runner) int {
	err := dispatch(args, stdout, stderr, runner)
	switch {
	case err == nil:
		return exitOK
	case check.IsFailure(err):
		fmt.Fprintf(stderr, "devc-verify: check failed: %v\n", err)
		return exitFalse
	default:
		fmt.Fprintf(stderr, "devc-verify: error: %v\n", err)
		return exitError
	}
}

func dispatch(args []string, stdout, stderr io.Writer, runner attest.Runner) error {
	if len(args) == 0 {
		return errors.New(usage)
	}
	cmd, rest := args[0], args[1:]
	fs := flag.NewFlagSet(cmd, flag.ContinueOnError)
	fs.SetOutput(stderr)
	var consumerDir, imageRef, patchFile string
	switch cmd {
	case "files", "verify", "decide":
		fs.StringVar(&consumerDir, "consumer-dir", "", "consumer checkout directory")
	case "attest":
		fs.StringVar(&imageRef, "image", "", "<repo>:<MAJOR>.<MINOR>@sha256:<digest>")
	default:
		return fmt.Errorf("unknown subcommand %q; %s", cmd, usage)
	}
	if cmd == "decide" {
		fs.StringVar(&patchFile, "patch", "", "file holding the compare API patch of .devcontainer/Dockerfile")
	}
	if err := fs.Parse(rest); err != nil {
		return err
	}
	if fs.NArg() != 0 {
		return fmt.Errorf("unexpected arguments %q", fs.Args())
	}
	if (cmd != "attest" && consumerDir == "") || (cmd == "attest" && imageRef == "") || (cmd == "decide" && patchFile == "") {
		return fmt.Errorf("%s: a required flag is missing; %s", cmd, usage)
	}

	ctx, cancel := context.WithTimeout(context.Background(), attestBudget)
	defer cancel()

	switch cmd {
	case "files":
		ref, err := consumer.Files(consumerDir)
		if err != nil {
			return err
		}
		return printRef(stdout, ref)
	case "attest":
		ref, err := image.Parse(imageRef)
		if err != nil {
			return err
		}
		return attest.Verify(ctx, runner, ref)
	case "verify":
		ref, err := consumer.Files(consumerDir)
		if err != nil {
			return err
		}
		return attest.Verify(ctx, runner, ref)
	default: // decide
		ref, err := consumer.Files(consumerDir)
		if err != nil {
			return err
		}
		patch, err := readPatch(patchFile)
		if err != nil {
			return err
		}
		// The offline predicate runs first: it is cheap, and a plain "no" needs no network.
		if err := bump.Predicate(patch, ref); err != nil {
			return err
		}
		return attest.Verify(ctx, runner, ref)
	}
}

func readPatch(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	b, err := io.ReadAll(io.LimitReader(f, maxPatchSize+1))
	if err != nil {
		return "", err
	}
	if len(b) > maxPatchSize {
		return "", fmt.Errorf("patch file is larger than %d bytes", maxPatchSize)
	}
	return string(b), nil
}

// printRef writes the one JSON line. Every value is constrained by the base-image regex.
func printRef(w io.Writer, ref image.Ref) error {
	return json.NewEncoder(w).Encode(struct {
		Image  string `json:"image"`
		Major  int    `json:"major"`
		Minor  int    `json:"minor"`
		Digest string `json:"digest"`
	}{ref.Repo(), ref.Major, ref.Minor, ref.Digest})
}
