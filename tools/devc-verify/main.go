// Command devc-verify is the gate's verification tool for consumers of the shared
// devcontainer images. See README.md for the CLI contract and exit codes.
package main

import (
	"context"
	"embed"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"time"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/attest"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/bump"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/consumer"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/image"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/rules"
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

// templates holds the previous release's template snapshot, templates/previous.devcontainer.json,
// when a release carries one (README.md, "Cutting a release"). It is built into the binary at
// the caller's pin, so it is the snapshot that release shipped.
//
//go:embed templates
var templates embed.FS

const snapshotPath = "templates/previous.devcontainer.json"

func snapshot() ([]byte, error) {
	b, err := templates.ReadFile(snapshotPath)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	return b, err
}

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
	var o consumer.Options
	var imageRef, patchFile, defaultBranch string
	switch cmd {
	case "files", "verify", "decide":
		fs.StringVar(&o.Dir, "consumer-dir", "", "the head's files, as fetch-consumer.sh wrote them")
		fs.StringVar(&o.TemplateDir, "template-dir", "", "the verifier checkout's template/ (holds .devcontainer/devcontainer.json)")
		fs.StringVar(&o.Repo, "repo", "", "github.repository, OWNER/REPO")
	case "attest":
		fs.StringVar(&imageRef, "image", "", "<repo>:<MAJOR>.<MINOR>@sha256:<digest>")
	default:
		return fmt.Errorf("unknown subcommand %q; %s", cmd, usage)
	}
	if cmd == "files" || cmd == "verify" {
		fs.StringVar(&o.BaseDir, "base-dir", "", "the PR base's files, as fetch-consumer.sh --mode-only wrote them")
		fs.StringVar(&o.TipDir, "tip-dir", "", "the default branch tip's files, as fetch-consumer.sh --mode-only wrote them")
	}
	if cmd == "verify" {
		fs.StringVar(&defaultBranch, "default-branch", "", "the repository's default branch, whose rules dev-App mode reads")
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
	var missing bool
	switch cmd {
	case "files":
		missing = o.Dir == ""
	case "attest":
		missing = imageRef == ""
	case "verify":
		missing = o.Dir == "" || o.BaseDir == "" || o.TipDir == "" || o.TemplateDir == "" || o.Repo == "" || defaultBranch == ""
	case "decide":
		missing = o.Dir == "" || patchFile == "" || o.TemplateDir == "" || o.Repo == ""
	}
	if missing {
		return fmt.Errorf("%s: a required flag is missing; %s", cmd, usage)
	}
	if cmd != "attest" {
		snap, err := snapshot()
		if err != nil {
			return err
		}
		o.Snapshot = snap
	}

	ctx, cancel := context.WithTimeout(context.Background(), attestBudget)
	defer cancel()

	switch cmd {
	case "files":
		res, err := consumer.Check(o)
		if err != nil {
			return err
		}
		return printRef(stdout, res)
	case "attest":
		ref, err := image.Parse(imageRef)
		if err != nil {
			return err
		}
		return attest.Verify(ctx, runner, ref)
	case "verify":
		res, err := consumer.Check(o)
		if err != nil {
			return err
		}
		if res.DevApp {
			if err := rules.RequireApproval(ctx, runner, o.Repo, defaultBranch); err != nil {
				return err
			}
		}
		return attest.Verify(ctx, runner, res.Ref)
	default: // decide
		// A dev-App image is never auto-merged (#418): refuse it before anything that could
		// error, so the answer is always a plain "no".
		head, err := consumer.HeadImage(o.Dir)
		if err != nil {
			return err
		}
		if head.DevApp() {
			return check.Failf("decide refuses dev-App image bumps: FROM %q", head.Raw)
		}
		res, err := consumer.Check(o)
		if err != nil {
			return err
		}
		patch, err := readPatch(patchFile)
		if err != nil {
			return err
		}
		// The offline predicate runs first: it is cheap, and a plain "no" needs no network.
		if err := bump.Predicate(patch, res.Ref); err != nil {
			return err
		}
		return attest.Verify(ctx, runner, res.Ref)
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
func printRef(w io.Writer, res consumer.Result) error {
	mode := "plain"
	if res.DevApp {
		mode = "dev-app"
	}
	ref := res.Ref
	return json.NewEncoder(w).Encode(struct {
		Image  string `json:"image"`
		Major  int    `json:"major"`
		Minor  int    `json:"minor"`
		Digest string `json:"digest"`
		Mode   string `json:"mode"`
	}{ref.Repo(), ref.Major, ref.Minor, ref.Digest, mode})
}
