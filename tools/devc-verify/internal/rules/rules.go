// Package rules checks the dev-App approval precondition (#418 owner decision 8): the default
// branch's effective rules must hold a pull_request rule that requires at least one approval
// and code-owner review. Rules from org rulesets count, since the endpoint returns every rule
// that applies to the branch. Bypass actors are not visible here, so "no bypass actor" stays a
// host procedure.
package rules

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/url"
	"regexp"
	"strings"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/attest"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
)

var (
	repoRE   = regexp.MustCompile(`^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$`)
	branchRE = regexp.MustCompile(`^[A-Za-z0-9._/-]+$`)
)

type rule struct {
	Type       string `json:"type"`
	Parameters struct {
		RequiredApprovingReviewCount *int  `json:"required_approving_review_count"`
		RequireCodeOwnerReview       *bool `json:"require_code_owner_review"`
	} `json:"parameters"`
}

// RequireApproval reads GET /repos/{repo}/rules/branches/{branch} with the caller's token
// (through gh, every page) and returns a *check.Failure unless a pull_request rule requires at
// least one approval and code-owner review. Any API or decoding error is an error, never a
// failure: a rule that cannot be read is red, and never reads as "no rule".
func RequireApproval(ctx context.Context, r attest.Runner, repo, branch string) error {
	if !repoRE.MatchString(repo) {
		return fmt.Errorf("repository %q is not OWNER/REPO", repo)
	}
	if !branchRE.MatchString(branch) || strings.Contains(branch, "..") {
		return fmt.Errorf("default branch %q has characters this check does not pass to the API", branch)
	}
	segs := strings.Split(branch, "/")
	for i, s := range segs {
		segs[i] = url.PathEscape(s)
	}
	out, err := r.Run(ctx, "gh", "api", "--paginate", "repos/"+repo+"/rules/branches/"+strings.Join(segs, "/"))
	if err != nil {
		return fmt.Errorf("reading the default branch's rules: %w", err)
	}
	// --paginate prints one JSON array per page, back to back.
	dec := json.NewDecoder(bytes.NewReader(out))
	pages := 0
	for {
		var page []rule
		err := dec.Decode(&page)
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return fmt.Errorf("the rules response does not decode: %q", err.Error())
		}
		pages++
		for _, ru := range page {
			p := ru.Parameters
			if ru.Type == "pull_request" && p.RequiredApprovingReviewCount != nil && *p.RequiredApprovingReviewCount >= 1 &&
				p.RequireCodeOwnerReview != nil && *p.RequireCodeOwnerReview {
				return nil
			}
		}
	}
	if pages == 0 {
		return errors.New("the rules response is empty")
	}
	return check.Failf("the default branch %q has no pull_request rule requiring at least 1 approval and code-owner review; a dev-App repo needs one before the dev App is installed", branch)
}
