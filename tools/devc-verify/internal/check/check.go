// Package check defines the error type that separates "the predicate is false" (a rule
// was plainly violated) from every other error (usage, I/O, gh or network failure,
// unparseable data). main maps the first to exit code 3 and the second to anything else,
// so an infrastructure fault can never read as a clean "no".
package check

import (
	"errors"
	"fmt"
)

// Failure is a plainly false predicate. Its message must quote (%q) any value derived
// from PR content.
type Failure struct{ msg string }

func (f *Failure) Error() string { return f.msg }

// Failf returns a *Failure with a formatted reason.
func Failf(format string, args ...any) error {
	return &Failure{msg: fmt.Sprintf(format, args...)}
}

// IsFailure reports whether err is, or wraps, a *Failure.
func IsFailure(err error) bool {
	var f *Failure
	return errors.As(err, &f)
}
