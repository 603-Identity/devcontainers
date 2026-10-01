// Package attest verifies an image's build provenance and SBOM attestations through the
// runner's gh CLI, then binds the signed statement to the image and to its tag.
package attest

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
)

// Runner runs an external command and returns its stdout. Tests inject a fake so the
// package is exercised offline against fixtures.
type Runner interface {
	Run(ctx context.Context, name string, args ...string) ([]byte, error)
}

// maxOutput bounds what a command may print, so a hostile or broken response cannot
// exhaust memory.
const maxOutput = 32 << 20

// ExecRunner runs real commands, inheriting the environment (gh reads GH_TOKEN).
type ExecRunner struct{}

type limitedBuffer struct {
	buf bytes.Buffer
	max int
}

func (l *limitedBuffer) Write(p []byte) (int, error) {
	if l.buf.Len()+len(p) > l.max {
		return 0, errors.New("command output exceeds the size limit")
	}
	return l.buf.Write(p)
}

// Run implements Runner. A non-zero exit is an error carrying the (quoted) stderr.
func (ExecRunner) Run(ctx context.Context, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	out := &limitedBuffer{max: maxOutput}
	errb := &limitedBuffer{max: 8 << 10}
	cmd.Stdout = out
	cmd.Stderr = errb
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("%s %q: %w; stderr %q", name, args[:min(len(args), 2)], err, errb.buf.String())
	}
	return out.buf.Bytes(), nil
}
