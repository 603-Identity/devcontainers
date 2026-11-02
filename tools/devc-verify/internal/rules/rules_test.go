package rules

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
)

type fake struct {
	out  string
	err  error
	args []string
}

func (f *fake) Run(_ context.Context, _ string, args ...string) ([]byte, error) {
	f.args = args
	return []byte(f.out), f.err
}

const (
	good    = `{"type":"pull_request","parameters":{"required_approving_review_count":1,"require_code_owner_review":true}}`
	checks  = `{"type":"required_status_checks","parameters":{"required_status_checks":[]}}`
	noOwner = `{"type":"pull_request","parameters":{"required_approving_review_count":2,"require_code_owner_review":false}}`
	zero    = `{"type":"pull_request","parameters":{"required_approving_review_count":0,"require_code_owner_review":true}}`
)

func TestRequireApproval(t *testing.T) {
	cases := map[string]struct {
		out     string
		err     error
		branch  string
		ok      bool
		failure bool // when !ok: a *check.Failure, else an error
	}{
		"one good rule":               {out: "[" + checks + "," + good + "]", ok: true},
		"good rule on a later page":   {out: "[" + checks + "]\n[" + good + "]", ok: true},
		"branch with a slash":         {out: "[" + good + "]", branch: "release/v1", ok: true},
		"no rules":                    {out: "[]", failure: true},
		"no code-owner review":        {out: "[" + noOwner + "]", failure: true},
		"zero approvals":              {out: "[" + zero + "]", failure: true},
		"missing parameters":          {out: `[{"type":"pull_request"}]`, failure: true},
		"other rule types only":       {out: "[" + checks + "]", failure: true},
		"API error":                   {err: errors.New("HTTP 404"), failure: false},
		"rate limited":                {err: errors.New("HTTP 429"), failure: false},
		"not JSON":                    {out: "<html>", failure: false},
		"empty response":              {out: "", failure: false},
		"object, not a list":          {out: `{"message":"Not Found"}`, failure: false},
		"bad branch is not requested": {branch: "a b", failure: false},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			f := &fake{out: c.out, err: c.err}
			b := c.branch
			if b == "" {
				b = "main"
			}
			err := RequireApproval(context.Background(), f, "glunk-works/app", b)
			switch {
			case c.ok && err != nil:
				t.Fatalf("want ok, got %v", err)
			case !c.ok && err == nil:
				t.Fatal("want a failure or an error, got ok")
			case !c.ok && check.IsFailure(err) != c.failure:
				t.Fatalf("failure=%v wanted, got %v", c.failure, err)
			}
			if c.ok && !strings.HasSuffix(strings.Join(f.args, " "), "repos/glunk-works/app/rules/branches/"+b) {
				t.Errorf("unexpected call %q", f.args)
			}
		})
	}
}
