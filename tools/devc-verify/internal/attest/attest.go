package attest

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/image"
)

const (
	sourceRepo    = "603-Identity/devcontainers"
	sourceRepoURL = "https://github.com/603-Identity/devcontainers"
	workflowPath  = ".github/workflows/build.yml"
	branchRef     = "refs/heads/main"
	certIdentity  = sourceRepoURL + "/" + workflowPath + "@" + branchRef
	oidcIssuer    = "https://token.actions.githubusercontent.com"

	provenanceType = "https://slsa.dev/provenance/v1"
	cyclonedxType  = "https://cyclonedx.org/bom"

	repositoryID      = "1392815879"
	repositoryOwnerID = "281691191"
)

var (
	// invocationRE accepts only attempt 1 (F4): a re-run signs .../attempts/2.
	invocationRE = regexp.MustCompile(`^` + regexp.QuoteMeta(sourceRepoURL) + `/actions/runs/([0-9]+)/attempts/1$`)

	allowedEvents = map[string]bool{"push": true, "schedule": true, "workflow_dispatch": true}
)

// idString decodes a JSON string or number: GitHub writes repository ids as strings in
// SLSA internalParameters, but this stays tolerant of the numeric form.
type idString string

func (s *idString) UnmarshalJSON(b []byte) error {
	var str string
	if err := json.Unmarshal(b, &str); err == nil {
		*s = idString(str)
		return nil
	}
	var n json.Number
	if err := json.Unmarshal(b, &n); err != nil {
		return err
	}
	*s = idString(n.String())
	return nil
}

// result is the part of one `gh attestation verify --format json` entry that is used.
type result struct {
	VerificationResult struct {
		Statement struct {
			PredicateType string `json:"predicateType"`
			Subject       []struct {
				Name   string            `json:"name"`
				Digest map[string]string `json:"digest"`
			} `json:"subject"`
			Predicate json.RawMessage `json:"predicate"`
		} `json:"statement"`
		Signature struct {
			Certificate struct {
				Issuer           string `json:"issuer"`
				BuildTrigger     string `json:"buildTrigger"`
				RunInvocationURI string `json:"runInvocationURI"`
			} `json:"certificate"`
		} `json:"signature"`
	} `json:"verificationResult"`
}

// provenance is the SLSA v1 predicate, by the field paths the spec lists.
type provenance struct {
	BuildDefinition struct {
		ExternalParameters struct {
			Workflow struct {
				Repository string `json:"repository"`
				Path       string `json:"path"`
				Ref        string `json:"ref"`
			} `json:"workflow"`
		} `json:"externalParameters"`
		InternalParameters struct {
			GitHub struct {
				EventName         string   `json:"event_name"`
				RepositoryID      idString `json:"repository_id"`
				RepositoryOwnerID idString `json:"repository_owner_id"`
			} `json:"github"`
		} `json:"internalParameters"`
	} `json:"buildDefinition"`
	RunDetails struct {
		Metadata struct {
			InvocationID string `json:"invocationId"`
		} `json:"metadata"`
	} `json:"runDetails"`
}

// Verify runs both `gh attestation verify` calls for ref, binds every result to the
// image, and checks the unsigned run_number against ref's MINOR.
//
// A failing gh call is an error, not a check failure: gh's exit code cannot tell a bad
// signature from a network fault, and an infrastructure fault must never read as a plain
// "no". A bad binding inside a verified statement is a *check.Failure.
func Verify(ctx context.Context, r Runner, ref image.Ref) error {
	prov, err := verifyOnce(ctx, r, ref, "")
	if err != nil {
		return err
	}
	runIDs := map[string]bool{}
	for i, res := range prov {
		id, err := bindProvenance(res, ref)
		if err != nil {
			return fmt.Errorf("provenance attestation %d: %w", i, err)
		}
		runIDs[id] = true
	}
	sbom, err := verifyOnce(ctx, r, ref, cyclonedxType)
	if err != nil {
		return err
	}
	for i, res := range sbom {
		if err := bindSubject(res, ref, cyclonedxType); err != nil {
			return fmt.Errorf("SBOM attestation %d: %w", i, err)
		}
	}
	for id := range runIDs {
		if err := checkRunNumber(ctx, r, id, ref.Minor); err != nil {
			return err
		}
	}
	return nil
}

func verifyOnce(ctx context.Context, r Runner, ref image.Ref, predicateType string) ([]result, error) {
	args := []string{
		"attestation", "verify", "oci://" + ref.Repo() + "@" + ref.Digest,
		"--repo", sourceRepo,
		"--cert-identity", certIdentity,
		"--cert-oidc-issuer", oidcIssuer,
		"--source-ref", branchRef,
		"--deny-self-hosted-runners",
		"--format", "json",
	}
	if predicateType != "" {
		args = append(args, "--predicate-type", predicateType)
	}
	out, err := r.Run(ctx, "gh", args...)
	if err != nil {
		return nil, fmt.Errorf("gh attestation verify failed: %w", err)
	}
	var res []result
	if err := json.Unmarshal(out, &res); err != nil {
		return nil, fmt.Errorf("gh attestation verify output is not the expected JSON: %w", err)
	}
	if len(res) == 0 {
		return nil, fmt.Errorf("gh attestation verify returned no results")
	}
	return res, nil
}

// bindSubject checks what both attestation kinds share: the predicate type, a subject
// carrying this image's repository and digest, and GitHub's OIDC issuer.
func bindSubject(res result, ref image.Ref, wantType string) error {
	st := res.VerificationResult.Statement
	if st.PredicateType != wantType {
		return check.Failf("predicate type is %q, want %q", st.PredicateType, wantType)
	}
	found := false
	for _, s := range st.Subject {
		if s.Name == ref.Repo() && "sha256:"+s.Digest["sha256"] == ref.Digest {
			found = true
		}
	}
	if !found {
		return check.Failf("no signed subject names %q with digest %q", ref.Repo(), ref.Digest)
	}
	if got := res.VerificationResult.Signature.Certificate.Issuer; got != oidcIssuer {
		return check.Failf("certificate issuer is %q, want %q", got, oidcIssuer)
	}
	return nil
}

// bindProvenance checks one provenance result and returns the run id it is bound to.
func bindProvenance(res result, ref image.Ref) (string, error) {
	if err := bindSubject(res, ref, provenanceType); err != nil {
		return "", err
	}
	var p provenance
	if err := json.Unmarshal(res.VerificationResult.Statement.Predicate, &p); err != nil {
		return "", check.Failf("provenance predicate does not decode: %q", err.Error())
	}
	wf := p.BuildDefinition.ExternalParameters.Workflow
	if wf.Repository != sourceRepoURL || wf.Path != workflowPath || wf.Ref != branchRef {
		return "", check.Failf("workflow is %q %q %q, want %q %q %q",
			wf.Repository, wf.Path, wf.Ref, sourceRepoURL, workflowPath, branchRef)
	}
	gh := p.BuildDefinition.InternalParameters.GitHub
	cert := res.VerificationResult.Signature.Certificate
	if !allowedEvents[gh.EventName] {
		return "", check.Failf("event_name %q is not push, schedule or workflow_dispatch", gh.EventName)
	}
	if gh.EventName != cert.BuildTrigger {
		return "", check.Failf("event_name %q disagrees with the certificate's buildTrigger %q", gh.EventName, cert.BuildTrigger)
	}
	if string(gh.RepositoryID) != repositoryID {
		return "", check.Failf("repository_id is %q, want %q", string(gh.RepositoryID), repositoryID)
	}
	if string(gh.RepositoryOwnerID) != repositoryOwnerID {
		return "", check.Failf("repository_owner_id is %q, want %q", string(gh.RepositoryOwnerID), repositoryOwnerID)
	}
	inv := p.RunDetails.Metadata.InvocationID
	m := invocationRE.FindStringSubmatch(inv)
	if m == nil {
		return "", check.Failf("invocationId %q is not %s/actions/runs/<id>/attempts/1", inv, sourceRepoURL)
	}
	if u := cert.RunInvocationURI; u != "" && u != inv {
		return "", check.Failf("certificate runInvocationURI %q disagrees with invocationId %q", u, inv)
	}
	return m[1], nil
}

// checkRunNumber is the one unsigned input: the run's number, read from the API, must
// equal the tag's MINOR (build.yml tags images <MAJOR>.<run_number>).
func checkRunNumber(ctx context.Context, r Runner, runID string, minor int) error {
	if _, err := strconv.ParseUint(runID, 10, 63); err != nil {
		return check.Failf("run id %q is not a number", runID)
	}
	out, err := r.Run(ctx, "gh", "api", "repos/"+sourceRepo+"/actions/runs/"+runID)
	if err != nil {
		return fmt.Errorf("gh api run %s failed: %w", runID, err)
	}
	var run struct {
		ID        json.Number `json:"id"`
		RunNumber *int        `json:"run_number"`
	}
	if err := json.Unmarshal(out, &run); err != nil || run.RunNumber == nil {
		return fmt.Errorf("run %s: response has no run_number", runID)
	}
	if id := strings.TrimSpace(run.ID.String()); id != "" && id != runID {
		return fmt.Errorf("run %s: response is for run %q", runID, id)
	}
	if *run.RunNumber != minor {
		return check.Failf("run %s has run_number %d but the tag's MINOR is %d", runID, *run.RunNumber, minor)
	}
	return nil
}
