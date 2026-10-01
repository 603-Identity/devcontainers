package devcontainer

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/603-identity/devcontainers/tools/devc-verify/internal/check"
)

func TestTemplateIsAccepted(t *testing.T) {
	b, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "template", ".devcontainer", "devcontainer.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err := Check(b); err != nil {
		t.Fatal(err)
	}
}

func TestAccepts(t *testing.T) {
	for name, src := range map[string]string{
		"build only":      `{"build":{"dockerfile":"Dockerfile"}}`,
		"with context":    `{"build":{"dockerfile":"Dockerfile","context":"."},"name":"x"}`,
		"comments+commas": "// c\n{ /* c */ \"build\": {\"dockerfile\": \"Dockerfile\",}, \"mounts\": [\"a\",],\n}",
		"other keys":      `{"build":{"dockerfile":"Dockerfile"},"Name":"x","remoteUser":"app"}`,
	} {
		if err := Check([]byte(src)); err != nil {
			t.Errorf("%s: %v", name, err)
		}
	}
}

func TestRejects(t *testing.T) {
	ok := `"build":{"dockerfile":"Dockerfile"}`
	cases := map[string]string{
		"image":                  `{` + ok + `,"image":"evil"}`,
		"Image":                  `{` + ok + `,"Image":"evil"}`,
		"image only":             `{"image":"ghcr.io/603-identity/devcontainer-tofu:4.1"}`,
		"__proto__ top level":    `{` + ok + `,"__proto__":{"dockerFile":"Evil"}}`,
		"__proto__ nested":       `{"build":{"dockerfile":"Dockerfile"},"customizations":{"__proto__":{}}}`,
		"escaped __proto__":      `{` + ok + `,"__proto__":{}}`,
		"dockerfile top":         `{` + ok + `,"dockerfile":"Dockerfile"}`,
		"DockerFile top":         `{` + ok + `,"DockerFile":"Evil.Dockerfile"}`,
		"L8 case pair":           `{` + ok + `,"dockerfile":"Dockerfile","DockerFile":"Evil.Dockerfile"}`,
		"legacy dockerFile":      `{` + ok + `,"dockerFile":"Evil.Dockerfile"}`,
		"top context":            `{` + ok + `,"context":".."}`,
		"dockerComposeFile":      `{` + ok + `,"dockerComposeFile":"compose.yml"}`,
		"features":               `{` + ok + `,"features":{"ghcr.io/x/y/z:1":{}}}`,
		"uppercase BUILD":        `{"BUILD":{"dockerfile":"Dockerfile"}}`,
		"Build":                  `{"Build":{"dockerfile":"Dockerfile"}}`,
		"no build":               `{"name":"x"}`,
		"build not object":       `{"build":"Dockerfile"}`,
		"build null":             `{"build":null}`,
		"build array":            `{"build":[{"dockerfile":"Dockerfile"}]}`,
		"empty build":            `{"build":{}}`,
		"build only context":     `{"build":{"context":"."}}`,
		"other dockerfile":       `{"build":{"dockerfile":"Evil.Dockerfile"}}`,
		"lowercase dockerfile v": `{"build":{"dockerfile":"dockerfile"}}`,
		"dockerfile path":        `{"build":{"dockerfile":"../Dockerfile"}}`,
		"dockerfile not string":  `{"build":{"dockerfile":["Dockerfile"]}}`,
		"build.DockerFile key":   `{"build":{"DockerFile":"Dockerfile"}}`,
		"build.dockerFile key":   `{"build":{"dockerFile":"Dockerfile"}}`,
		"context parent":         `{"build":{"dockerfile":"Dockerfile","context":".."}}`,
		"context subdir":         `{"build":{"dockerfile":"Dockerfile","context":"x"}}`,
		"build.args":             `{"build":{"dockerfile":"Dockerfile","args":{"A":"1"}}}`,
		"build.target":           `{"build":{"dockerfile":"Dockerfile","target":"evil"}}`,
		"build.options":          `{"build":{"dockerfile":"Dockerfile","options":["--x"]}}`,
		"build.cacheFrom":        `{"build":{"dockerfile":"Dockerfile","cacheFrom":"evil"}}`,
		"duplicate build":        `{"build":{"dockerfile":"Dockerfile"},"build":{"dockerfile":"Dockerfile"}}`,
		"escaped duplicate":      `{"build":{"dockerfile":"Dockerfile"},"build":{"dockerfile":"Evil.Dockerfile"}}`,
		"escaped duplicate rev":  `{"build":{"dockerfile":"Evil.Dockerfile"},"build":{"dockerfile":"Dockerfile"}}`,
		"duplicate nested":       `{"build":{"dockerfile":"Dockerfile","dockerfile":"Evil"}}`,
		"escaped nested dup":     `{"build":{"dockerfile":"Dockerfile","dockerfile":"Evil"}}`,
		"duplicate other key":    `{` + ok + `,"name":"a","name":"b"}`,
		"duplicate in array":     `{` + ok + `,"a":[{"k":1,"k":2}]}`,
		"escaped image":          `{` + ok + `,"image":"evil"}`,
		"not JSON":               `{`,
		"empty":                  ``,
		"array":                  `[]`,
		"scalar":                 `"build"`,
		"null":                   `null`,
		"trailing value":         `{` + ok + `} {}`,
		"unterminated comment":   `{` + ok + `} /* `,
		"too deep":               `{` + ok + `,"a":` + strings.Repeat("[", 100) + strings.Repeat("]", 100) + `}`,
	}
	for name, src := range cases {
		t.Run(name, func(t *testing.T) {
			err := Check([]byte(src))
			if !check.IsFailure(err) {
				t.Fatalf("want a check failure, got %v", err)
			}
		})
	}
}
