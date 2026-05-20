# Cliban CLI Extensions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add eight CLI extensions to cliban that let the skill suite store and mutate spec/plan/activity content in issue and milestone descriptions atomically.

**Architecture:** A new `internal/descmd/` package isolates all markdown description parsing (pure functions, heavily tested). Store-layer methods wrap descmd in single SQL transactions so concurrent mutations are serialized by SQLite. New CLI commands and flags are added in `internal/cli/`. No schema changes — milestone already has a `description` column.

**Tech Stack:** Go 1.26, cobra (CLI), SQLite (storage), standard library `strings`/`bufio` (markdown parsing — no external markdown lib; we own the contract).

**Working directory:** `/home/alex/dev/cliban`. All paths in this plan are relative to that directory unless prefixed with `/`.

**Background spec:** [[2026-05-20-cliban-driven-workflow-design]] §"Cliban CLI Extensions" and §"Data Layout Conventions".

---

## File Structure

| Path | Role |
|---|---|
| `internal/descmd/descmd.go` | **NEW.** Pure description-parsing functions: section finder, task/step finder, mutators (tick, append-log, rewrite-step). Operates on `string` input/output. No DB. |
| `internal/descmd/descmd_test.go` | **NEW.** Unit tests for descmd. |
| `internal/store/issue.go` | **MODIFY.** Add `TickStep`, `AppendActivityLog`, `PromoteStep` store methods. Extend `ListIssuesFilter` with `UpdatedSince`. |
| `internal/cli/milestone.go` | **MODIFY.** Add `--description-file` flag to `add` and `edit`. |
| `internal/cli/issue.go` | **MODIFY.** Add `--section` flag to `show`. Add `--pager` flag to `show`. Add `--updated-since` flag to `ls`. Register new subcommands. |
| `internal/cli/issue_workflow.go` | **NEW.** Cobra subcommands for `tick`, `promote`, `log`, `current`. Keeps `issue.go` from growing past 1500 lines and groups workflow-mutation commands together. |
| `internal/cli/issue_workflow_test.go` | **NEW.** End-to-end tests for the new subcommands using the existing test scaffolding. |
| `README.md` | **MODIFY.** Document the parseable-description contract. |

---

## Task 1: descmd — section finder

**Files:**
- Create: `internal/descmd/descmd.go`
- Test: `internal/descmd/descmd_test.go`

- [ ] **Step 1: Create the package with a failing test for `FindSection`**

`internal/descmd/descmd_test.go`:
```go
package descmd

import "testing"

func TestFindSection_Found(t *testing.T) {
	desc := "## Spec\n\nhello\n\n## Plan\n\n### Task 1: foo\n"
	start, end, ok := FindSection(desc, "Spec")
	if !ok {
		t.Fatalf("expected to find ## Spec section")
	}
	got := desc[start:end]
	want := "\nhello\n\n"
	if got != want {
		t.Fatalf("content mismatch:\n got=%q\nwant=%q", got, want)
	}
}

func TestFindSection_NotFound(t *testing.T) {
	desc := "no sections here"
	if _, _, ok := FindSection(desc, "Spec"); ok {
		t.Fatalf("expected not found")
	}
}

func TestFindSection_LastSection(t *testing.T) {
	desc := "## Spec\n\nhello world"
	start, end, ok := FindSection(desc, "Spec")
	if !ok {
		t.Fatalf("expected found")
	}
	got := desc[start:end]
	want := "\nhello world"
	if got != want {
		t.Fatalf("content mismatch:\n got=%q\nwant=%q", got, want)
	}
}
```

- [ ] **Step 2: Run the test; expect compile failure (package empty)**

```bash
cd /home/alex/dev/cliban
go test ./internal/descmd/...
```

Expected: `internal/descmd/descmd.go: no such file or directory` or "undefined: FindSection".

- [ ] **Step 3: Implement `FindSection`**

`internal/descmd/descmd.go`:
```go
// Package descmd parses and mutates the cliban issue/milestone description
// markdown contract. The contract is documented in the cliban README under
// "Description contract". All functions are pure: input string in, output
// string + error out. The store layer wraps these in SQL transactions so
// mutations are atomic.
package descmd

import (
	"fmt"
	"strings"
)

// FindSection locates a top-level H2 section by its exact anchor text
// (the part after "## "). It returns the [start, end) byte offsets of the
// section's *content* — i.e. everything after the heading line up to (but
// not including) the next H2 heading or end of string.
//
// Matching rules:
//   - Anchor match is case-sensitive and exact (no leading/trailing spaces).
//   - The heading must appear at the start of a line.
//   - Content includes the leading newline after the heading and the
//     trailing newlines up to the next ## heading.
func FindSection(desc, anchor string) (start, end int, found bool) {
	needle := "## " + anchor
	lines := strings.SplitAfter(desc, "\n")
	offset := 0
	sectionContentStart := -1
	for _, line := range lines {
		lineLen := len(line)
		trimmed := strings.TrimRight(line, "\n")
		if sectionContentStart < 0 {
			if trimmed == needle {
				sectionContentStart = offset + lineLen
			}
		} else if strings.HasPrefix(trimmed, "## ") {
			return sectionContentStart, offset, true
		}
		offset += lineLen
	}
	if sectionContentStart < 0 {
		return 0, 0, false
	}
	return sectionContentStart, len(desc), true
}

// errf is a small helper for constructing descmd errors with structured prefixes.
func errf(format string, args ...any) error {
	return fmt.Errorf("descmd: "+format, args...)
}

```

- [ ] **Step 4: Run the test; expect PASS**

```bash
go test ./internal/descmd/...
```

Expected: `PASS`, all three subtests green.

- [ ] **Step 5: Add edge-case tests for partial matches and similar anchors**

Append to `internal/descmd/descmd_test.go`:
```go
func TestFindSection_NoFalseMatchOnPrefix(t *testing.T) {
	desc := "## Specification\n\nnot spec\n"
	if _, _, ok := FindSection(desc, "Spec"); ok {
		t.Fatalf("anchor %q must not match %q (exact match required)", "Spec", "## Specification")
	}
}

func TestFindSection_NoFalseMatchOnH3(t *testing.T) {
	desc := "### Spec\n\nnot a top-level section\n"
	if _, _, ok := FindSection(desc, "Spec"); ok {
		t.Fatalf("must not match H3 ### Spec as a section")
	}
}
```

- [ ] **Step 6: Run the new tests; expect PASS (the implementation already handles these)**

```bash
go test ./internal/descmd/... -run TestFindSection -v
```

Expected: PASS for both new subtests.

- [ ] **Step 7: Commit**

```bash
git add internal/descmd/descmd.go internal/descmd/descmd_test.go
git commit -m "feat(descmd): add FindSection for H2 anchor lookup"
```

---

## Task 2: descmd — task and step finders

**Files:**
- Modify: `internal/descmd/descmd.go`
- Test: `internal/descmd/descmd_test.go`

- [ ] **Step 1: Write failing test for `FindTask`**

Append to `internal/descmd/descmd_test.go`:
```go
func TestFindTask_Found(t *testing.T) {
	plan := "\n### Task 1: foo\n\nbody1\n\n### Task 2: bar\n\nbody2\n"
	start, end, ok := FindTask(plan, 1)
	if !ok {
		t.Fatalf("expected to find Task 1")
	}
	got := plan[start:end]
	want := "\nbody1\n\n"
	if got != want {
		t.Fatalf("content mismatch:\n got=%q\nwant=%q", got, want)
	}
}

func TestFindTask_NotFound(t *testing.T) {
	plan := "\n### Task 1: foo\n"
	if _, _, ok := FindTask(plan, 2); ok {
		t.Fatalf("expected Task 2 not found")
	}
}

func TestFindTask_LastTask(t *testing.T) {
	plan := "\n### Task 1: foo\n\nbody1\n"
	start, end, ok := FindTask(plan, 1)
	if !ok {
		t.Fatalf("expected found")
	}
	if plan[start:end] != "\nbody1\n" {
		t.Fatalf("got=%q want=%q", plan[start:end], "\nbody1\n")
	}
}
```

- [ ] **Step 2: Run; expect FAIL (FindTask undefined)**

```bash
go test ./internal/descmd/... -run TestFindTask
```

- [ ] **Step 3: Implement `FindTask`**

Append to `internal/descmd/descmd.go`:
```go
// FindTask locates the N-th task within a plan-section body. Tasks are
// identified by an H3 heading of the form "### Task <N>:" at the start of a
// line. Returns the [start, end) byte offsets of the task's body — content
// between this Task heading and the next "### " heading or end of string.
func FindTask(planBody string, n int) (start, end int, found bool) {
	prefix := fmt.Sprintf("### Task %d:", n)
	lines := strings.SplitAfter(planBody, "\n")
	offset := 0
	taskBodyStart := -1
	for _, line := range lines {
		lineLen := len(line)
		trimmed := strings.TrimRight(line, "\n")
		if taskBodyStart < 0 {
			if strings.HasPrefix(trimmed, prefix) {
				taskBodyStart = offset + lineLen
			}
		} else if strings.HasPrefix(trimmed, "### ") {
			return taskBodyStart, offset, true
		}
		offset += lineLen
	}
	if taskBodyStart < 0 {
		return 0, 0, false
	}
	return taskBodyStart, len(planBody), true
}
```

- [ ] **Step 4: Run tests; expect PASS**

```bash
go test ./internal/descmd/... -run TestFindTask
```

- [ ] **Step 5: Write failing test for `FindStep`**

Append to `internal/descmd/descmd_test.go`:
```go
func TestFindStep_Found(t *testing.T) {
	task := "\n- [ ] **Step 1: foo**\n- [ ] **Step 2: bar**\n- [x] **Step 3: baz**\n"
	step, ok := FindStep(task, 2)
	if !ok {
		t.Fatalf("expected to find step 2")
	}
	if step.Checked {
		t.Fatalf("step 2 should be unchecked")
	}
	if got := task[step.LineStart:step.LineEnd]; got != "- [ ] **Step 2: bar**\n" {
		t.Fatalf("line content mismatch: %q", got)
	}
}

func TestFindStep_AlreadyChecked(t *testing.T) {
	task := "\n- [ ] **Step 1: foo**\n- [x] **Step 2: bar**\n"
	step, ok := FindStep(task, 2)
	if !ok {
		t.Fatalf("expected found")
	}
	if !step.Checked {
		t.Fatalf("step 2 should be checked")
	}
}

func TestFindStep_OutOfRange(t *testing.T) {
	task := "\n- [ ] **Step 1: foo**\n"
	if _, ok := FindStep(task, 2); ok {
		t.Fatalf("step 2 should not exist")
	}
}

func TestFindStep_IndentedChildIgnored(t *testing.T) {
	task := "\n- [ ] **Step 1: foo**\n  - some nested bullet\n- [ ] **Step 2: bar**\n"
	step, ok := FindStep(task, 2)
	if !ok {
		t.Fatalf("expected step 2 found")
	}
	if got := strings.TrimRight(task[step.LineStart:step.LineEnd], "\n"); got != "- [ ] **Step 2: bar**" {
		t.Fatalf("got=%q", got)
	}
}
```

- [ ] **Step 6: Run; expect FAIL**

```bash
go test ./internal/descmd/... -run TestFindStep
```

- [ ] **Step 7: Implement `FindStep`**

Append to `internal/descmd/descmd.go`:
```go
// Step describes one bite-sized step line in a Task body.
type Step struct {
	Index     int    // 1-based step index within the task
	Checked   bool   // current checkbox state
	LineStart int    // byte offset of the line start within the task body
	LineEnd   int    // byte offset just past the trailing newline (or len(task) if last)
	Raw       string // the full line content including trailing newline
}

// FindStep locates the M-th step line in a task body. Steps are top-level
// GFM checkbox list items: lines beginning with "- [ ] " or "- [x] " at
// column zero. Indented child bullets are ignored.
func FindStep(taskBody string, m int) (Step, bool) {
	lines := strings.SplitAfter(taskBody, "\n")
	offset := 0
	count := 0
	for _, line := range lines {
		lineLen := len(line)
		if strings.HasPrefix(line, "- [ ] ") || strings.HasPrefix(line, "- [x] ") {
			count++
			if count == m {
				return Step{
					Index:     m,
					Checked:   strings.HasPrefix(line, "- [x] "),
					LineStart: offset,
					LineEnd:   offset + lineLen,
					Raw:       line,
				}, true
			}
		}
		offset += lineLen
	}
	return Step{}, false
}
```

- [ ] **Step 8: Run tests; expect PASS**

```bash
go test ./internal/descmd/...
```

- [ ] **Step 9: Commit**

```bash
git add internal/descmd/descmd.go internal/descmd/descmd_test.go
git commit -m "feat(descmd): add FindTask and FindStep for plan parsing"
```

---

## Task 3: descmd — mutations (TickStep, AppendActivityLog, RewriteStepLine)

**Files:**
- Modify: `internal/descmd/descmd.go`
- Test: `internal/descmd/descmd_test.go`

- [ ] **Step 1: Failing test for `TickStep`**

Update `internal/descmd/descmd_test.go` to add `"strings"` to its imports (the new tests use `strings.Contains` to assert error messages):
```go
import (
	"strings"
	"testing"
)
```

Then append:
```go
func TestTickStep_HappyPath(t *testing.T) {
	desc := "## Spec\n\nx\n\n## Plan\n\n### Task 1: foo\n\n- [ ] **Step 1: a**\n- [ ] **Step 2: b**\n"
	out, err := TickStep(desc, 1, 2)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := "## Spec\n\nx\n\n## Plan\n\n### Task 1: foo\n\n- [ ] **Step 1: a**\n- [x] **Step 2: b**\n"
	if out != want {
		t.Fatalf("output mismatch:\n got=%q\nwant=%q", out, want)
	}
}

func TestTickStep_AlreadyChecked(t *testing.T) {
	desc := "## Plan\n\n### Task 1: foo\n\n- [x] **Step 1: a**\n"
	_, err := TickStep(desc, 1, 1)
	if err == nil || !strings.Contains(err.Error(), "already checked") {
		t.Fatalf("expected already-checked error, got %v", err)
	}
}

func TestTickStep_NoPlanSection(t *testing.T) {
	desc := "## Spec\n\nonly spec here\n"
	_, err := TickStep(desc, 1, 1)
	if err == nil || !strings.Contains(err.Error(), "no ## Plan section") {
		t.Fatalf("expected no-plan error, got %v", err)
	}
}

func TestTickStep_NoTask(t *testing.T) {
	desc := "## Plan\n\n### Task 1: foo\n\n- [ ] **Step 1: a**\n"
	_, err := TickStep(desc, 5, 1)
	if err == nil || !strings.Contains(err.Error(), "no Task 5") {
		t.Fatalf("expected no-task error, got %v", err)
	}
}

func TestTickStep_NoStep(t *testing.T) {
	desc := "## Plan\n\n### Task 1: foo\n\n- [ ] **Step 1: a**\n"
	_, err := TickStep(desc, 1, 9)
	if err == nil || !strings.Contains(err.Error(), "no Step 9") {
		t.Fatalf("expected no-step error, got %v", err)
	}
}
```

- [ ] **Step 2: Run; expect FAIL**

```bash
go test ./internal/descmd/... -run TestTickStep
```

- [ ] **Step 3: Implement `TickStep`**

Append to `internal/descmd/descmd.go`:
```go
// TickStep flips the M-th step of task N in the description from
// "- [ ] ..." to "- [x] ...". Returns the rewritten description.
// Returns a non-nil error if the ## Plan section is missing, the task is
// missing, the step is missing, or the step is already checked.
func TickStep(desc string, taskN, stepM int) (string, error) {
	planStart, planEnd, ok := FindSection(desc, "Plan")
	if !ok {
		return "", errf("no ## Plan section")
	}
	planBody := desc[planStart:planEnd]
	taskStart, taskEnd, ok := FindTask(planBody, taskN)
	if !ok {
		return "", errf("no Task %d in ## Plan", taskN)
	}
	taskBody := planBody[taskStart:taskEnd]
	step, ok := FindStep(taskBody, stepM)
	if !ok {
		return "", errf("no Step %d in Task %d", stepM, taskN)
	}
	if step.Checked {
		return "", errf("Step %d of Task %d already checked", stepM, taskN)
	}
	// Absolute offset of the step line inside the original desc.
	abs := planStart + taskStart + step.LineStart
	// The step line is guaranteed to start with "- [ ] ".
	newLine := "- [x] " + step.Raw[len("- [ ] "):]
	return desc[:abs] + newLine + desc[abs+len(step.Raw):], nil
}
```

- [ ] **Step 4: Run tests; expect PASS**

```bash
go test ./internal/descmd/... -run TestTickStep
```

- [ ] **Step 5: Failing test for `AppendActivityLog`**

Add `"time"` to the imports of `internal/descmd/descmd_test.go`, then append:
```go
func TestAppendActivityLog_ExistingSection(t *testing.T) {
	desc := "## Spec\n\nfoo\n\n## Activity Log\n\n- 2026-05-19T10:00Z — earlier\n"
	ts, _ := time.Parse(time.RFC3339, "2026-05-20T13:42:00Z")
	out := AppendActivityLog(desc, "promoted Step 3", ts)
	want := "## Spec\n\nfoo\n\n## Activity Log\n\n- 2026-05-19T10:00Z — earlier\n- 2026-05-20T13:42Z — promoted Step 3\n"
	if out != want {
		t.Fatalf("output mismatch:\n got=%q\nwant=%q", out, want)
	}
}

func TestAppendActivityLog_CreatesSectionWhenAbsent(t *testing.T) {
	desc := "## Spec\n\nfoo\n"
	ts, _ := time.Parse(time.RFC3339, "2026-05-20T13:42:00Z")
	out := AppendActivityLog(desc, "first entry", ts)
	want := "## Spec\n\nfoo\n\n## Activity Log\n\n- 2026-05-20T13:42Z — first entry\n"
	if out != want {
		t.Fatalf("output mismatch:\n got=%q\nwant=%q", out, want)
	}
}

func TestAppendActivityLog_EmptyDescription(t *testing.T) {
	ts, _ := time.Parse(time.RFC3339, "2026-05-20T13:42:00Z")
	out := AppendActivityLog("", "first entry", ts)
	want := "## Activity Log\n\n- 2026-05-20T13:42Z — first entry\n"
	if out != want {
		t.Fatalf("output mismatch:\n got=%q\nwant=%q", out, want)
	}
}
```

- [ ] **Step 6: Run; expect FAIL**

```bash
go test ./internal/descmd/... -run TestAppendActivityLog
```

- [ ] **Step 7: Implement `AppendActivityLog`**

Add `"time"` to the imports of `internal/descmd/descmd.go` (the package didn't need it before this step). Then append:
```go
// AppendActivityLog appends a chronological entry to the "## Activity Log"
// section. The entry is formatted as "- <UTC-ts> — <msg>". If the section
// does not exist, one is created at the end of the description. The
// timestamp is rendered as RFC-3339-minutes ("2006-01-02T15:04Z") in UTC.
func AppendActivityLog(desc, msg string, ts time.Time) string {
	stamp := ts.UTC().Format("2006-01-02T15:04Z")
	entry := fmt.Sprintf("- %s — %s\n", stamp, msg)
	start, end, ok := FindSection(desc, "Activity Log")
	if !ok {
		sep := ""
		if desc != "" {
			sep = "\n"
			if !strings.HasSuffix(desc, "\n") {
				sep = "\n\n"
			} else if !strings.HasSuffix(desc, "\n\n") {
				sep = "\n"
			}
		}
		return desc + sep + "## Activity Log\n\n" + entry
	}
	// Insert the entry just before the section-end offset. Ensure exactly
	// one trailing newline between the previous content and the new entry.
	body := desc[start:end]
	trimmed := strings.TrimRight(body, "\n")
	suffix := body[len(trimmed):]
	rebuilt := trimmed + "\n" + entry + suffix
	if !strings.HasSuffix(rebuilt, "\n") {
		rebuilt += "\n"
	}
	return desc[:start] + rebuilt + desc[end:]
}
```

- [ ] **Step 8: Run tests; expect PASS**

```bash
go test ./internal/descmd/... -run TestAppendActivityLog -v
```

- [ ] **Step 9: Failing test for `RewriteStepLine`**

Append to `internal/descmd/descmd_test.go`:
```go
func TestRewriteStepLine_HappyPath(t *testing.T) {
	desc := "## Plan\n\n### Task 1: foo\n\n- [ ] **Step 1: a**\n- [ ] **Step 2: b**\n"
	out, err := RewriteStepLine(desc, 1, 2, "- [ ] **Step 2: b** → CLI-99\n")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := "## Plan\n\n### Task 1: foo\n\n- [ ] **Step 1: a**\n- [ ] **Step 2: b** → CLI-99\n"
	if out != want {
		t.Fatalf("output mismatch:\n got=%q\nwant=%q", out, want)
	}
}

func TestRewriteStepLine_MissingNewline(t *testing.T) {
	_, err := RewriteStepLine("## Plan\n\n### Task 1: foo\n\n- [ ] x\n", 1, 1, "no newline")
	if err == nil || !strings.Contains(err.Error(), "must end with newline") {
		t.Fatalf("expected newline-required error, got %v", err)
	}
}
```

- [ ] **Step 10: Run; expect FAIL**

```bash
go test ./internal/descmd/... -run TestRewriteStepLine
```

- [ ] **Step 11: Implement `RewriteStepLine`**

Append to `internal/descmd/descmd.go`:
```go
// RewriteStepLine replaces the M-th step line in task N with the provided
// newLine. newLine must end with a single newline character. Returns the
// rewritten description.
func RewriteStepLine(desc string, taskN, stepM int, newLine string) (string, error) {
	if !strings.HasSuffix(newLine, "\n") {
		return "", errf("newLine must end with newline")
	}
	planStart, planEnd, ok := FindSection(desc, "Plan")
	if !ok {
		return "", errf("no ## Plan section")
	}
	planBody := desc[planStart:planEnd]
	taskStart, taskEnd, ok := FindTask(planBody, taskN)
	if !ok {
		return "", errf("no Task %d in ## Plan", taskN)
	}
	taskBody := planBody[taskStart:taskEnd]
	step, ok := FindStep(taskBody, stepM)
	if !ok {
		return "", errf("no Step %d in Task %d", stepM, taskN)
	}
	abs := planStart + taskStart + step.LineStart
	return desc[:abs] + newLine + desc[abs+len(step.Raw):], nil
}
```

- [ ] **Step 12: Run all descmd tests; expect PASS**

```bash
go test ./internal/descmd/... -v
```

- [ ] **Step 13: Commit**

```bash
git add internal/descmd/descmd.go internal/descmd/descmd_test.go
git commit -m "feat(descmd): add TickStep, AppendActivityLog, RewriteStepLine"
```

---

## Task 4: Milestone --description-file flag

**Files:**
- Modify: `internal/cli/milestone.go:30-65` (add subcommand), `:188-232` (edit subcommand)
- Test: `internal/cli/milestone_cmd_test.go`

- [ ] **Step 1: Failing test for milestone add with --description-file**

Append to `internal/cli/milestone_cmd_test.go` (uses the existing `runCLI` helper from `project_cmd_test.go`):
```go
func TestMilestoneAdd_DescriptionFile(t *testing.T) {
	dir := t.TempDir()
	descPath := filepath.Join(dir, "desc.md")
	body := "## Spec\n\nmilestone goal here\n"
	if err := os.WriteFile(descPath, []byte(body), 0o600); err != nil {
		t.Fatalf("write desc: %v", err)
	}
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "MS", "--name", "Milestones"); c != 0 {
		t.Fatal("project add")
	}
	if _, _, c := runCLI(t, "milestone", "add", "--project", "MS", "--name", "v0.1", "--description-file", descPath); c != 0 {
		t.Fatalf("milestone add code=%d", c)
	}
	out, _, c := runCLI(t, "milestone", "show", "v0.1", "--project", "MS", "--json")
	if c != 0 {
		t.Fatalf("show code=%d out=%s", c, out)
	}
	var m map[string]any
	if err := json.Unmarshal([]byte(out), &m); err != nil {
		t.Fatalf("parse json: %v: %s", err, out)
	}
	if got := m["description"]; got != body {
		t.Fatalf("description mismatch:\n got=%v\nwant=%q", got, body)
	}
}
```

Ensure the file's imports include `encoding/json`, `os`, `path/filepath`, and `testing`.

- [ ] **Step 2: Run; expect FAIL ("unknown flag --description-file")**

```bash
go test ./internal/cli/ -run TestMilestoneAdd_DescriptionFile
```

- [ ] **Step 3: Add --description-file to milestone add**

Modify `internal/cli/milestone.go:30-65`. Replace the function `milestoneAddCmd` body to read:
```go
func milestoneAddCmd() *cobra.Command {
	var project, name, desc, descFile, target string
	var asJSON bool
	c := &cobra.Command{
		Use:   "add",
		Short: "Add a milestone",
		RunE: func(cmd *cobra.Command, args []string) error {
			s, err := openStore()
			if err != nil {
				return err
			}
			defer s.Close()
			tgt, err := parseTarget(target)
			if err != nil {
				return err
			}
			descChanged := cmd.Flags().Changed("description")
			descFileChanged := cmd.Flags().Changed("description-file")
			effDesc, _, err := resolveDescription(desc, descFile, descChanged, descFileChanged)
			if err != nil {
				return err
			}
			m, err := s.CreateMilestone(strings.ToUpper(project), name, effDesc, tgt)
			if err != nil {
				return err
			}
			if asJSON {
				return WriteJSON(cmd.OutOrStdout(), milestoneToJSON(s, m))
			}
			fmt.Fprintf(cmd.OutOrStdout(), "created milestone %s in %s\n", m.Name, strings.ToUpper(project))
			return nil
		},
	}
	c.Flags().StringVar(&project, "project", "", "project key (required)")
	c.Flags().StringVar(&name, "name", "", "milestone name (required)")
	c.Flags().StringVar(&desc, "description", "", "description")
	c.Flags().StringVar(&descFile, "description-file", "", "read description from a file (use '-' for stdin)")
	c.Flags().StringVar(&target, "target", "", "target date YYYY-MM-DD")
	c.Flags().BoolVar(&asJSON, "json", false, "JSON output")
	_ = c.MarkFlagRequired("project")
	_ = c.MarkFlagRequired("name")
	return c
}
```

- [ ] **Step 4: Run the test; expect PASS**

```bash
go test ./internal/cli/ -run TestMilestoneAdd_DescriptionFile
```

- [ ] **Step 5: Failing test for milestone edit with --description-file**

Append to `internal/cli/milestone_cmd_test.go`:
```go
func TestMilestoneEdit_DescriptionFile(t *testing.T) {
	dir := t.TempDir()
	descPath := filepath.Join(dir, "desc.md")
	body := "updated body\n"
	if err := os.WriteFile(descPath, []byte(body), 0o600); err != nil {
		t.Fatalf("write desc: %v", err)
	}
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "ME", "--name", "MilestoneEdit"); c != 0 {
		t.Fatal("project add")
	}
	if _, _, c := runCLI(t, "milestone", "add", "--project", "ME", "--name", "v1", "--description", "initial"); c != 0 {
		t.Fatal("milestone add")
	}
	if _, _, c := runCLI(t, "milestone", "edit", "--project", "ME", "--name", "v1", "--description-file", descPath); c != 0 {
		t.Fatalf("milestone edit code=%d", c)
	}
	out, _, c := runCLI(t, "milestone", "show", "v1", "--project", "ME", "--json")
	if c != 0 {
		t.Fatalf("show code=%d", c)
	}
	var m map[string]any
	if err := json.Unmarshal([]byte(out), &m); err != nil {
		t.Fatalf("parse json: %v", err)
	}
	if got := m["description"]; got != body {
		t.Fatalf("description mismatch: got=%v want=%q", got, body)
	}
}
```

- [ ] **Step 6: Run; expect FAIL**

```bash
go test ./internal/cli/ -run TestMilestoneEdit_DescriptionFile
```

- [ ] **Step 7: Add --description-file to milestone edit**

Modify `internal/cli/milestone.go:188-232`. Replace `milestoneEditCmd` body:
```go
func milestoneEditCmd() *cobra.Command {
	var project, name, rename, desc, descFile, status, target string
	var clearTarget bool
	c := &cobra.Command{
		Use:   "edit",
		Short: "Edit a milestone",
		RunE: func(cmd *cobra.Command, args []string) error {
			s, err := openStore()
			if err != nil {
				return err
			}
			defer s.Close()
			params := store.UpdateMilestoneParams{}
			if cmd.Flags().Changed("rename") {
				params.NewName = &rename
			}
			descChanged := cmd.Flags().Changed("description")
			descFileChanged := cmd.Flags().Changed("description-file")
			effDesc, descSet, err := resolveDescription(desc, descFile, descChanged, descFileChanged)
			if err != nil {
				return err
			}
			if descSet {
				params.Description = &effDesc
			}
			if cmd.Flags().Changed("status") {
				params.Status = &status
			}
			if clearTarget {
				params.ClearTarget = true
			} else if cmd.Flags().Changed("target") {
				tgt, err := parseTarget(target)
				if err != nil {
					return err
				}
				params.TargetDate = tgt
			}
			return s.UpdateMilestone(strings.ToUpper(project), name, params)
		},
	}
	c.Flags().StringVar(&project, "project", "", "project key (required)")
	c.Flags().StringVar(&name, "name", "", "milestone name (required)")
	c.Flags().StringVar(&rename, "rename", "", "new name")
	c.Flags().StringVar(&desc, "description", "", "new description")
	c.Flags().StringVar(&descFile, "description-file", "", "read description from a file (use '-' for stdin)")
	c.Flags().StringVar(&status, "status", "", "new status (open|completed|cancelled)")
	c.Flags().StringVar(&target, "target", "", "new target date YYYY-MM-DD")
	c.Flags().BoolVar(&clearTarget, "clear-target", false, "clear target date")
	_ = c.MarkFlagRequired("project")
	_ = c.MarkFlagRequired("name")
	return c
}
```

- [ ] **Step 8: Run all milestone tests; expect PASS**

```bash
go test ./internal/cli/ -run TestMilestone -v
```

- [ ] **Step 9: Commit**

```bash
git add internal/cli/milestone.go internal/cli/milestone_cmd_test.go
git commit -m "feat(milestone): support --description-file on add and edit"
```

---

## Task 5: issue ls --updated-since

**Files:**
- Modify: `internal/store/issue.go:166-242` (ListIssuesFilter + ListIssues)
- Modify: `internal/cli/issue.go:319-407` (issueListCmd)
- Test: `internal/cli/issue_cmd_test.go`

- [ ] **Step 1: Failing test for `--updated-since`**

Append to `internal/cli/issue_cmd_test.go` (ensure imports include `encoding/json`, `strings`, `testing`, and `time`):
```go
func TestIssueLs_UpdatedSince_Duration(t *testing.T) {
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "USN", "--name", "UpdSince"); c != 0 {
		t.Fatal("project add")
	}
	if _, _, c := runCLI(t, "issue", "add", "--project", "USN", "--title", "old issue"); c != 0 {
		t.Fatal("old add")
	}
	time.Sleep(1100 * time.Millisecond)
	if _, _, c := runCLI(t, "issue", "add", "--project", "USN", "--title", "fresh issue"); c != 0 {
		t.Fatal("fresh add")
	}
	out, _, c := runCLI(t, "issue", "ls", "--project", "USN", "--updated-since", "1s", "--json")
	if c != 0 {
		t.Fatalf("ls code=%d out=%s", c, out)
	}
	var titles []string
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		if line == "" {
			continue
		}
		var m map[string]any
		if err := json.Unmarshal([]byte(line), &m); err != nil {
			t.Fatalf("parse: %v", err)
		}
		titles = append(titles, m["title"].(string))
	}
	if len(titles) != 1 || titles[0] != "fresh issue" {
		t.Fatalf("expected exactly fresh issue; got %v", titles)
	}
}

func TestIssueLs_UpdatedSince_Timestamp(t *testing.T) {
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "UST", "--name", "UpdSinceTs"); c != 0 {
		t.Fatal("project add")
	}
	if _, _, c := runCLI(t, "issue", "add", "--project", "UST", "--title", "issue 1"); c != 0 {
		t.Fatal("add 1")
	}
	cutoff := time.Now().UTC().Format(time.RFC3339)
	time.Sleep(1100 * time.Millisecond)
	if _, _, c := runCLI(t, "issue", "add", "--project", "UST", "--title", "issue 2"); c != 0 {
		t.Fatal("add 2")
	}
	out, _, c := runCLI(t, "issue", "ls", "--project", "UST", "--updated-since", cutoff, "--json")
	if c != 0 {
		t.Fatalf("ls code=%d", c)
	}
	if !strings.Contains(out, "issue 2") || strings.Contains(out, "issue 1") {
		t.Fatalf("expected only issue 2; got %s", out)
	}
}
```

- [ ] **Step 2: Run; expect FAIL ("unknown flag --updated-since")**

```bash
go test ./internal/cli/ -run TestIssueLs_UpdatedSince
```

- [ ] **Step 3: Extend `ListIssuesFilter` in `internal/store/issue.go`**

Modify `internal/store/issue.go:166-176` to add `UpdatedSince`:
```go
type ListIssuesFilter struct {
	ProjectKey      string
	Status          domain.Status
	Priority        domain.Priority
	MilestoneName   string
	ParentKey       *domain.IssueKey
	NoSubs          bool
	IncludeArchived bool
	LabelNames      []string
	UpdatedSince    *time.Time // optional; if set, only issues with updated_at >= this UTC time
}
```

Add the filter clause inside `ListIssues` after the `LabelNames` loop (around line 216):
```go
	if f.UpdatedSince != nil {
		conds = append(conds, "i.updated_at >= ?")
		args = append(args, f.UpdatedSince.UTC().Format(time.RFC3339Nano))
	}
```

- [ ] **Step 4: Parse `--updated-since` in CLI**

Modify `internal/cli/issue.go:319-407`. Add a flag and a helper:

In the function body (around the other `if status != ""` parsing), add:
```go
	if updatedSinceFlag != "" {
		ts, err := parseUpdatedSince(updatedSinceFlag, time.Now())
		if err != nil {
			return err
		}
		f.UpdatedSince = &ts
	}
```

In the flag block:
```go
	c.Flags().StringVar(&updatedSinceFlag, "updated-since", "", "filter issues updated within a duration (e.g. 4h) or since an RFC3339 timestamp")
```

Declare `updatedSinceFlag` at the top of the function with the other `var` declarations.

Append a helper near `sortIssues` in the same file:
```go
// parseUpdatedSince accepts either a duration ("4h", "30m") or an
// RFC3339 timestamp and returns the absolute UTC time to filter from.
func parseUpdatedSince(s string, now time.Time) (time.Time, error) {
	if d, err := time.ParseDuration(s); err == nil {
		return now.UTC().Add(-d), nil
	}
	if t, err := time.Parse(time.RFC3339, s); err == nil {
		return t.UTC(), nil
	}
	if t, err := time.Parse(time.RFC3339Nano, s); err == nil {
		return t.UTC(), nil
	}
	return time.Time{}, fmt.Errorf("%w: invalid --updated-since %q (want duration like 4h or RFC3339 timestamp)", store.ErrValidation, s)
}
```

- [ ] **Step 5: Run tests; expect PASS**

```bash
go test ./internal/cli/ -run TestIssueLs_UpdatedSince -v
go test ./internal/store/...
```

- [ ] **Step 6: Commit**

```bash
git add internal/store/issue.go internal/cli/issue.go internal/cli/issue_cmd_test.go
git commit -m "feat(issue): add --updated-since filter for ls"
```

---

## Task 6: issue show --section

**Files:**
- Modify: `internal/cli/issue.go:481-...` (issueShowCmd)
- Test: `internal/cli/issue_cmd_test.go`

- [ ] **Step 1: Failing test for `--section spec`**

Append to `internal/cli/issue_cmd_test.go` (uses tempfiles for description input — the existing `runCLI` helper doesn't drive stdin):
```go
// writeIssueDesc creates a tempfile with the given body and adds an issue
// whose description is read from that file. Returns the resulting issue key.
func writeIssueDesc(t *testing.T, project, title, body string) {
	t.Helper()
	p := filepath.Join(t.TempDir(), "desc.md")
	if err := os.WriteFile(p, []byte(body), 0o600); err != nil {
		t.Fatalf("write desc: %v", err)
	}
	if _, _, c := runCLI(t, "issue", "add", "--project", project, "--title", title, "--description-file", p); c != 0 {
		t.Fatalf("issue add code=%d", c)
	}
}

func TestIssueShow_Section_Spec(t *testing.T) {
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "SEC", "--name", "Sect"); c != 0 {
		t.Fatal("project add")
	}
	body := "## Spec\n\nthe spec body\n\n## Plan\n\n### Task 1: foo\n\n- [ ] **Step 1: a**\n"
	writeIssueDesc(t, "SEC", "test", body)
	out, _, c := runCLI(t, "issue", "show", "SEC-1", "--section", "spec")
	if c != 0 {
		t.Fatalf("show code=%d out=%s", c, out)
	}
	if !strings.Contains(out, "the spec body") {
		t.Fatalf("expected spec body in output; got %q", out)
	}
	if strings.Contains(out, "the spec body\n\n## Plan") {
		t.Fatalf("section output should stop at next H2; got %q", out)
	}
}

func TestIssueShow_Section_NotFound(t *testing.T) {
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "SEC2", "--name", "Sect2"); c != 0 {
		t.Fatal("project add")
	}
	writeIssueDesc(t, "SEC2", "no plan", "## Spec\n\njust spec\n")
	_, errOut, c := runCLI(t, "issue", "show", "SEC2-1", "--section", "plan")
	if c == 0 {
		t.Fatal("expected non-zero exit for missing plan section")
	}
	if !strings.Contains(errOut, "no ## Plan section") {
		t.Fatalf("expected no-plan error; got %q", errOut)
	}
}
```

- [ ] **Step 2: Run; expect FAIL**

```bash
go test ./internal/cli/ -run TestIssueShow_Section
```

- [ ] **Step 3: Wire `--section` into `issueShowCmd`**

Modify `internal/cli/issue.go:481-...`. Add flag and branch:

```go
func issueShowCmd() *cobra.Command {
	var asJSON bool
	var section string
	c := &cobra.Command{
		Use:   "show <KEY>",
		Short: "Show an issue",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			s, err := openStore()
			if err != nil {
				return err
			}
			defer s.Close()
			k, err := domain.ParseIssueKey(args[0])
			if err != nil {
				return err
			}
			issue, err := s.GetIssueByKey(k)
			if err != nil {
				return err
			}
			if section != "" {
				anchor, err := sectionAnchor(section)
				if err != nil {
					return err
				}
				start, end, ok := descmd.FindSection(issue.Description, anchor)
				if !ok {
					return fmt.Errorf("%w: no ## %s section in %s", store.ErrNotFound, anchor, args[0])
				}
				fmt.Fprint(cmd.OutOrStdout(), issue.Description[start:end])
				return nil
			}
			// ... existing behavior unchanged below ...
```

Add the helper and the import in the same file:
```go
import (
	// ... existing imports ...
	"github.com/alex/cliban/internal/descmd"
)

// sectionAnchor maps a --section short name to the canonical H2 anchor text.
func sectionAnchor(s string) (string, error) {
	switch s {
	case "spec":
		return "Spec", nil
	case "plan":
		return "Plan", nil
	case "activity":
		return "Activity Log", nil
	case "notes":
		return "Notes", nil
	default:
		return "", fmt.Errorf("%w: invalid --section %q (want spec|plan|activity|notes)", store.ErrValidation, s)
	}
}
```

Add the flag declaration before `return c`:
```go
	c.Flags().StringVar(&section, "section", "", "show only one section: spec|plan|activity|notes")
```

Take care to leave the rest of `issueShowCmd` body (JSON/table rendering) intact — only add the `if section != ""` early-return.

- [ ] **Step 4: Run tests; expect PASS**

```bash
go test ./internal/cli/ -run TestIssueShow_Section -v
```

- [ ] **Step 5: Commit**

```bash
git add internal/cli/issue.go internal/cli/issue_cmd_test.go
git commit -m "feat(issue): add --section flag to show"
```

---

## Task 7: issue current (git-branch → issue lookup)

**Files:**
- Create: `internal/cli/issue_workflow.go`
- Create: `internal/cli/issue_workflow_test.go`
- Modify: `internal/cli/issue.go:18-23` (register subcommand)

- [ ] **Step 1: Failing test for `issue current`**

`internal/cli/issue_workflow_test.go`:
```go
package cli

import (
	"encoding/json"
	"os"
	"strings"
	"testing"
)

func TestIssueCurrent_BranchMatches(t *testing.T) {
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "CUR", "--name", "Current"); c != 0 {
		t.Fatal("project add")
	}
	if _, _, c := runCLI(t, "issue", "add", "--project", "CUR", "--title", "hello world"); c != 0 {
		t.Fatal("issue add")
	}
	os.Setenv("CLIBAN_CURRENT_BRANCH_OVERRIDE", "cur-1-hello-world")
	t.Cleanup(func() { os.Unsetenv("CLIBAN_CURRENT_BRANCH_OVERRIDE") })

	out, _, c := runCLI(t, "issue", "current", "--json")
	if c != 0 {
		t.Fatalf("current code=%d out=%s", c, out)
	}
	var m map[string]any
	if err := json.Unmarshal([]byte(out), &m); err != nil {
		t.Fatalf("parse: %v: %s", err, out)
	}
	if m["key"] != "CUR-1" {
		t.Fatalf("expected CUR-1, got %v", m["key"])
	}
}

func TestIssueCurrent_NoBranchMatch(t *testing.T) {
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "NCB", "--name", "NoBranch"); c != 0 {
		t.Fatal("project add")
	}
	os.Setenv("CLIBAN_CURRENT_BRANCH_OVERRIDE", "main")
	t.Cleanup(func() { os.Unsetenv("CLIBAN_CURRENT_BRANCH_OVERRIDE") })

	_, errOut, c := runCLI(t, "issue", "current", "--json")
	if c == 0 {
		t.Fatal("expected non-zero exit for unmatched branch")
	}
	if !strings.Contains(errOut, "no issue found for current branch") {
		t.Fatalf("unexpected error: %s", errOut)
	}
}
```

The `CLIBAN_CURRENT_BRANCH_OVERRIDE` env var is the test hook that bypasses real `git` invocation (introduced by the implementation in Step 3 below).

- [ ] **Step 2: Run; expect FAIL**

```bash
go test ./internal/cli/ -run TestIssueCurrent
```

- [ ] **Step 3: Implement `issue current` in a new file**

`internal/cli/issue_workflow.go`:
```go
package cli

import (
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"

	"github.com/alex/cliban/internal/domain"
	"github.com/alex/cliban/internal/store"
	"github.com/spf13/cobra"
)

// branchIssueRE matches a cliban-style git branch name and captures the
// project key + seq. Example: "cli-12-fix-column-ordering" → ("cli", "12").
var branchIssueRE = regexp.MustCompile(`^([a-z][a-z0-9]+)-(\d+)(?:-|$)`)

// currentBranch returns the current git branch name. The
// CLIBAN_CURRENT_BRANCH_OVERRIDE env var lets tests substitute a value
// without invoking git.
func currentBranch() (string, error) {
	if v := os.Getenv("CLIBAN_CURRENT_BRANCH_OVERRIDE"); v != "" {
		return v, nil
	}
	cmd := exec.Command("git", "branch", "--show-current")
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("git branch --show-current: %w", err)
	}
	return strings.TrimSpace(string(out)), nil
}

func issueCurrentCmd() *cobra.Command {
	var asJSON bool
	c := &cobra.Command{
		Use:   "current",
		Short: "Show the issue inferred from the current git branch",
		RunE: func(cmd *cobra.Command, args []string) error {
			branch, err := currentBranch()
			if err != nil {
				return err
			}
			match := branchIssueRE.FindStringSubmatch(branch)
			if match == nil {
				return fmt.Errorf("%w: no issue found for current branch %q", store.ErrNotFound, branch)
			}
			key := domain.IssueKey{Project: strings.ToUpper(match[1])}
			fmt.Sscanf(match[2], "%d", &key.Seq)
			s, err := openStore()
			if err != nil {
				return err
			}
			defer s.Close()
			issue, err := s.GetIssueByKey(key)
			if err != nil {
				return fmt.Errorf("%w: no issue found for current branch %q (parsed %s)", store.ErrNotFound, branch, key)
			}
			projects := projectKeysByID(s)
			pk := projects[issue.ProjectID]
			if asJSON {
				return WriteIssueJSON(cmd.OutOrStdout(), issueJSONInputs(s, projects, pk, issue))
			}
			fmt.Fprintf(cmd.OutOrStdout(), "%s-%d %s\n", pk, issue.Seq, issue.Title)
			return nil
		},
	}
	c.Flags().BoolVar(&asJSON, "json", false, "JSON output")
	return c
}
```

- [ ] **Step 4: Register the subcommand**

Modify `internal/cli/issue.go:20-22`:
```go
	c.AddCommand(issueAddCmd(), issueListCmd(), issueShowCmd(), issueEditCmd(), issueMvCmd(), issueRmCmd(),
		issueArchiveCmd(), issueUnarchiveCmd(), issueArchiveDoneCmd(), issueImportCmd(), issueBlockedCmd(),
		issueCurrentCmd())
```

- [ ] **Step 5: Run tests; expect PASS**

```bash
go test ./internal/cli/ -run TestIssueCurrent -v
```

- [ ] **Step 6: Commit**

```bash
git add internal/cli/issue.go internal/cli/issue_workflow.go internal/cli/issue_workflow_test.go
git commit -m "feat(issue): add 'current' subcommand for git-branch → issue lookup"
```

---

## Task 8: issue tick

**Files:**
- Modify: `internal/store/issue.go` (add `TickStep` method)
- Modify: `internal/cli/issue_workflow.go` (add subcommand)
- Modify: `internal/cli/issue.go:20-22` (register subcommand)
- Modify: `internal/cli/issue_workflow_test.go`

- [ ] **Step 1: Failing test for `issue tick`**

Append to `internal/cli/issue_workflow_test.go` (and add `"os"`, `"path/filepath"` to imports if not present). Reuse `writeIssueDesc` from Task 6 — if Task 6 hasn't been merged yet for this engineer, copy the helper definition here:
```go
func TestIssueTick_HappyPath(t *testing.T) {
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "TCK", "--name", "Tick"); c != 0 {
		t.Fatal("project add")
	}
	body := "## Plan\n\n### Task 1: foo\n\n- [ ] **Step 1: a**\n- [ ] **Step 2: b**\n"
	writeIssueDesc(t, "TCK", "tick-test", body)
	if _, _, c := runCLI(t, "issue", "tick", "TCK-1", "--task", "1", "--step", "2", "--json"); c != 0 {
		t.Fatalf("tick code=%d", c)
	}
	out, _, c := runCLI(t, "issue", "show", "TCK-1", "--section", "plan")
	if c != 0 {
		t.Fatalf("show code=%d", c)
	}
	if !strings.Contains(out, "- [x] **Step 2: b**") {
		t.Fatalf("expected step 2 ticked; description was:\n%s", out)
	}
}

func TestIssueTick_AlreadyChecked(t *testing.T) {
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "TCK2", "--name", "Tick2"); c != 0 {
		t.Fatal("project add")
	}
	body := "## Plan\n\n### Task 1: foo\n\n- [x] **Step 1: a**\n"
	writeIssueDesc(t, "TCK2", "already", body)
	_, errOut, c := runCLI(t, "issue", "tick", "TCK2-1", "--task", "1", "--step", "1")
	if c == 0 {
		t.Fatal("expected non-zero exit for already-checked step")
	}
	if c != 2 {
		t.Fatalf("expected exit code 2 (validation), got %d: %s", c, errOut)
	}
	if !strings.Contains(errOut, "already checked") {
		t.Fatalf("expected already-checked error, got %q", errOut)
	}
}

func TestIssueTick_NoPlanSection(t *testing.T) {
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "TCK3", "--name", "Tick3"); c != 0 {
		t.Fatal("project add")
	}
	writeIssueDesc(t, "TCK3", "no plan", "just a description with no plan section\n")
	_, errOut, c := runCLI(t, "issue", "tick", "TCK3-1", "--task", "1", "--step", "1")
	if c == 0 {
		t.Fatal("expected non-zero exit for missing plan section")
	}
	if !strings.Contains(errOut, "no ## Plan section") {
		t.Fatalf("expected no-plan error, got %q", errOut)
	}
}
```

- [ ] **Step 2: Run; expect FAIL**

```bash
go test ./internal/cli/ -run TestIssueTick
```

- [ ] **Step 3: Add `TickStep` store method**

Append to `internal/store/issue.go`:
```go
// TickStep flips the M-th step of task N in the description of issue k from
// unchecked to checked. The mutation is wrapped in a single SQL transaction
// so concurrent ticks are serialized by SQLite. Returns the updated step
// info (task index, step index, new check state, new updated_at).
type TickResult struct {
	Key       domain.IssueKey
	TaskN     int
	StepM     int
	Checked   bool
	UpdatedAt time.Time
}

func (s *Store) TickStep(k domain.IssueKey, taskN, stepM int) (*TickResult, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInternal, err)
	}
	defer tx.Rollback()

	var id int64
	var desc string
	if err := tx.QueryRow(`SELECT i.id, i.description FROM issue i JOIN project p ON p.id=i.project_id WHERE p.key=? AND i.seq=?`, k.Project, k.Seq).
		Scan(&id, &desc); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("%w: %v", ErrInternal, err)
	}
	newDesc, err := descmd.TickStep(desc, taskN, stepM)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrValidation, err)
	}
	now := s.nowISO()
	if _, err := tx.Exec(`UPDATE issue SET description=?, updated_at=? WHERE id=?`, newDesc, now, id); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInternal, err)
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInternal, err)
	}
	ts, _ := time.Parse(time.RFC3339Nano, now)
	return &TickResult{Key: k, TaskN: taskN, StepM: stepM, Checked: true, UpdatedAt: ts}, nil
}
```

Add the descmd import at the top of `internal/store/issue.go`:
```go
import (
	// ... existing imports ...
	"github.com/alex/cliban/internal/descmd"
)
```

- [ ] **Step 4: Add `issue tick` CLI command**

Append to `internal/cli/issue_workflow.go`:
```go
func issueTickCmd() *cobra.Command {
	var taskN, stepM int
	var asJSON bool
	c := &cobra.Command{
		Use:   "tick <KEY>",
		Short: "Atomically tick a step in the issue's ## Plan section",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			k, err := domain.ParseIssueKey(args[0])
			if err != nil {
				return err
			}
			s, err := openStore()
			if err != nil {
				return err
			}
			defer s.Close()
			res, err := s.TickStep(k, taskN, stepM)
			if err != nil {
				return err
			}
			if asJSON {
				return WriteJSON(cmd.OutOrStdout(), map[string]any{
					"key":        args[0],
					"task":       res.TaskN,
					"step":       res.StepM,
					"checked":    res.Checked,
					"updated_at": res.UpdatedAt,
				})
			}
			fmt.Fprintf(cmd.OutOrStdout(), "ticked %s Task %d Step %d\n", args[0], res.TaskN, res.StepM)
			return nil
		},
	}
	c.Flags().IntVar(&taskN, "task", 0, "task number (required, 1-indexed)")
	c.Flags().IntVar(&stepM, "step", 0, "step number (required, 1-indexed)")
	c.Flags().BoolVar(&asJSON, "json", false, "JSON output")
	_ = c.MarkFlagRequired("task")
	_ = c.MarkFlagRequired("step")
	return c
}
```

- [ ] **Step 5: Register the subcommand**

Modify `internal/cli/issue.go:20-22`:
```go
	c.AddCommand(issueAddCmd(), issueListCmd(), issueShowCmd(), issueEditCmd(), issueMvCmd(), issueRmCmd(),
		issueArchiveCmd(), issueUnarchiveCmd(), issueArchiveDoneCmd(), issueImportCmd(), issueBlockedCmd(),
		issueCurrentCmd(), issueTickCmd())
```

- [ ] **Step 6: Run tests; expect PASS**

```bash
go test ./internal/cli/ -run TestIssueTick -v
go test ./internal/store/...
```

- [ ] **Step 7: Commit**

```bash
git add internal/store/issue.go internal/cli/issue.go internal/cli/issue_workflow.go internal/cli/issue_workflow_test.go
git commit -m "feat(issue): add 'tick' command for atomic step checkbox toggle"
```

---

## Task 9: issue log

**Files:**
- Modify: `internal/store/issue.go` (add `AppendActivityLog` method)
- Modify: `internal/cli/issue_workflow.go` (add subcommand)
- Modify: `internal/cli/issue.go:20-22` (register subcommand)
- Modify: `internal/cli/issue_workflow_test.go`

- [ ] **Step 1: Failing test for `issue log`**

Append to `internal/cli/issue_workflow_test.go`. The stdin-based test uses a tempfile rather than stdin because the existing `runCLI` helper doesn't drive stdin:
```go
func TestIssueLog_AppendsEntry(t *testing.T) {
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "LOG", "--name", "Log"); c != 0 {
		t.Fatal("project add")
	}
	writeIssueDesc(t, "LOG", "logtest", "## Spec\n\nx\n")
	if _, _, c := runCLI(t, "issue", "log", "LOG-1", "first entry", "--json"); c != 0 {
		t.Fatalf("log 1 code=%d", c)
	}
	if _, _, c := runCLI(t, "issue", "log", "LOG-1", "second entry", "--json"); c != 0 {
		t.Fatalf("log 2 code=%d", c)
	}
	out, _, c := runCLI(t, "issue", "show", "LOG-1", "--section", "activity")
	if c != 0 {
		t.Fatalf("show code=%d", c)
	}
	if !strings.Contains(out, "first entry") || !strings.Contains(out, "second entry") {
		t.Fatalf("expected both entries; got:\n%s", out)
	}
	if strings.Index(out, "first entry") > strings.Index(out, "second entry") {
		t.Fatalf("entries should be in chronological order:\n%s", out)
	}
}

func TestIssueLog_CreatesSectionIfAbsent(t *testing.T) {
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "LOG2", "--name", "Log2"); c != 0 {
		t.Fatal("project add")
	}
	writeIssueDesc(t, "LOG2", "noactivity", "")
	if _, _, c := runCLI(t, "issue", "log", "LOG2-1", "hello"); c != 0 {
		t.Fatalf("log code=%d", c)
	}
	out, _, c := runCLI(t, "issue", "show", "LOG2-1", "--section", "activity")
	if c != 0 {
		t.Fatalf("show code=%d", c)
	}
	if !strings.Contains(out, "hello") {
		t.Fatalf("expected 'hello' in section, got:\n%s", out)
	}
}

func TestIssueLog_MessageFile(t *testing.T) {
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "LOG3", "--name", "Log3"); c != 0 {
		t.Fatal("project add")
	}
	writeIssueDesc(t, "LOG3", "filetest", "")
	msgPath := filepath.Join(t.TempDir(), "msg.txt")
	if err := os.WriteFile(msgPath, []byte("multi-line\nmessage from file"), 0o600); err != nil {
		t.Fatalf("write msg: %v", err)
	}
	if _, _, c := runCLI(t, "issue", "log", "LOG3-1", "--message-file", msgPath); c != 0 {
		t.Fatalf("log code=%d", c)
	}
	out, _, c := runCLI(t, "issue", "show", "LOG3-1", "--section", "activity")
	if c != 0 {
		t.Fatalf("show code=%d", c)
	}
	if !strings.Contains(out, "multi-line") {
		t.Fatalf("expected file message, got:\n%s", out)
	}
}
```

- [ ] **Step 2: Run; expect FAIL**

```bash
go test ./internal/cli/ -run TestIssueLog
```

- [ ] **Step 3: Add `AppendActivityLog` store method**

Append to `internal/store/issue.go`:
```go
type LogResult struct {
	Key       domain.IssueKey
	Entry     string
	Timestamp time.Time
}

// AppendActivityLog atomically appends a chronological entry to the
// ## Activity Log section of the issue's description, creating the section
// if absent.
func (s *Store) AppendActivityLog(k domain.IssueKey, message string) (*LogResult, error) {
	if message == "" {
		return nil, fmt.Errorf("%w: message required", ErrValidation)
	}
	tx, err := s.db.Begin()
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInternal, err)
	}
	defer tx.Rollback()

	var id int64
	var desc string
	if err := tx.QueryRow(`SELECT i.id, i.description FROM issue i JOIN project p ON p.id=i.project_id WHERE p.key=? AND i.seq=?`, k.Project, k.Seq).
		Scan(&id, &desc); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("%w: %v", ErrInternal, err)
	}
	now := time.Now().UTC()
	newDesc := descmd.AppendActivityLog(desc, message, now)
	nowISO := s.nowISO()
	if _, err := tx.Exec(`UPDATE issue SET description=?, updated_at=? WHERE id=?`, newDesc, nowISO, id); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInternal, err)
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInternal, err)
	}
	return &LogResult{Key: k, Entry: message, Timestamp: now}, nil
}
```

- [ ] **Step 4: Add `issue log` CLI command**

Append to `internal/cli/issue_workflow.go`:
```go
func issueLogCmd() *cobra.Command {
	var messageFile string
	var asJSON bool
	c := &cobra.Command{
		Use:   "log <KEY> [<message>]",
		Short: "Atomically append an entry to the issue's ## Activity Log section",
		Args:  cobra.RangeArgs(1, 2),
		RunE: func(cmd *cobra.Command, args []string) error {
			k, err := domain.ParseIssueKey(args[0])
			if err != nil {
				return err
			}
			msg := ""
			if len(args) == 2 {
				msg = args[1]
			}
			if cmd.Flags().Changed("message-file") {
				if msg != "" {
					return fmt.Errorf("%w: pass <message> OR --message-file, not both", store.ErrValidation)
				}
				if messageFile == "-" {
					b, err := io.ReadAll(cmd.InOrStdin())
					if err != nil {
						return err
					}
					msg = strings.TrimRight(string(b), "\n")
				} else {
					b, err := os.ReadFile(messageFile)
					if err != nil {
						return fmt.Errorf("%w: %v", store.ErrValidation, err)
					}
					msg = strings.TrimRight(string(b), "\n")
				}
			}
			if msg == "" {
				return fmt.Errorf("%w: message required (positional or --message-file)", store.ErrValidation)
			}
			s, err := openStore()
			if err != nil {
				return err
			}
			defer s.Close()
			res, err := s.AppendActivityLog(k, msg)
			if err != nil {
				return err
			}
			if asJSON {
				return WriteJSON(cmd.OutOrStdout(), map[string]any{
					"key":       args[0],
					"entry":     res.Entry,
					"timestamp": res.Timestamp,
				})
			}
			fmt.Fprintf(cmd.OutOrStdout(), "logged on %s: %s\n", args[0], res.Entry)
			return nil
		},
	}
	c.Flags().StringVar(&messageFile, "message-file", "", "read message from file (use '-' for stdin)")
	c.Flags().BoolVar(&asJSON, "json", false, "JSON output")
	return c
}
```

Add `"io"` and `"os"` imports to `issue_workflow.go` if not already present.

- [ ] **Step 5: Register the subcommand**

Modify `internal/cli/issue.go:20-22`:
```go
	c.AddCommand(issueAddCmd(), issueListCmd(), issueShowCmd(), issueEditCmd(), issueMvCmd(), issueRmCmd(),
		issueArchiveCmd(), issueUnarchiveCmd(), issueArchiveDoneCmd(), issueImportCmd(), issueBlockedCmd(),
		issueCurrentCmd(), issueTickCmd(), issueLogCmd())
```

- [ ] **Step 6: Run tests; expect PASS**

```bash
go test ./internal/cli/ -run TestIssueLog -v
```

- [ ] **Step 7: Commit**

```bash
git add internal/store/issue.go internal/cli/issue.go internal/cli/issue_workflow.go internal/cli/issue_workflow_test.go
git commit -m "feat(issue): add 'log' command for atomic Activity Log append"
```

---

## Task 10: issue promote

**Files:**
- Modify: `internal/store/issue.go` (add `PromoteStep` method)
- Modify: `internal/cli/issue_workflow.go` (add subcommand)
- Modify: `internal/cli/issue.go:20-22` (register subcommand)
- Modify: `internal/cli/issue_workflow_test.go`

- [ ] **Step 1: Failing test for `issue promote`**

Append to `internal/cli/issue_workflow_test.go`:
```go
func TestIssuePromote_SubIssue(t *testing.T) {
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "PRM", "--name", "Promote"); c != 0 {
		t.Fatal("project add")
	}
	body := "## Plan\n\n### Task 1: foo\n\n- [ ] **Step 1: do thing**\n- [ ] **Step 2: bigger thing**\n"
	writeIssueDesc(t, "PRM", "parent", body)
	out, _, c := runCLI(t, "issue", "promote", "PRM-1",
		"--task", "1", "--step", "2", "--title", "Bigger thing as own issue",
		"--as", "sub-issue", "--json")
	if c != 0 {
		t.Fatalf("promote code=%d out=%s", c, out)
	}
	var m map[string]any
	if err := json.Unmarshal([]byte(out), &m); err != nil {
		t.Fatalf("parse: %v: %s", err, out)
	}
	if got, _ := m["new_key"].(string); got != "PRM-2" {
		t.Fatalf("expected new_key PRM-2, got %v", m["new_key"])
	}
	planOut, _, c := runCLI(t, "issue", "show", "PRM-1", "--section", "plan")
	if c != 0 {
		t.Fatalf("show plan code=%d", c)
	}
	if !strings.Contains(planOut, "→ PRM-2") {
		t.Fatalf("expected step line rewritten with arrow; got:\n%s", planOut)
	}
	subOut, _, c := runCLI(t, "issue", "show", "PRM-2", "--json")
	if c != 0 {
		t.Fatalf("show sub code=%d", c)
	}
	if !strings.Contains(subOut, `"parent": "PRM-1"`) {
		t.Fatalf("expected PRM-2 to be sub-issue of PRM-1; got:\n%s", subOut)
	}
}

func TestIssuePromote_Related(t *testing.T) {
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "REL", "--name", "Rel"); c != 0 {
		t.Fatal("project add")
	}
	writeIssueDesc(t, "REL", "parent",
		"## Plan\n\n### Task 1: foo\n\n- [ ] **Step 1: do thing**\n")
	out, _, c := runCLI(t, "issue", "promote", "REL-1",
		"--task", "1", "--step", "1", "--title", "Related work",
		"--as", "related", "--json")
	if c != 0 {
		t.Fatalf("promote code=%d", c)
	}
	var m map[string]any
	if err := json.Unmarshal([]byte(out), &m); err != nil {
		t.Fatalf("parse: %v", err)
	}
	newKey, _ := m["new_key"].(string)
	relOut, _, c := runCLI(t, "issue", "show", newKey, "--json")
	if c != 0 {
		t.Fatalf("show new code=%d", c)
	}
	if !strings.Contains(relOut, `"type": "related_to"`) || !strings.Contains(relOut, `"target": "REL-1"`) {
		t.Fatalf("expected related_to relation to REL-1; got:\n%s", relOut)
	}
}

func TestIssuePromote_InvalidAs(t *testing.T) {
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "PI", "--name", "PromInv"); c != 0 {
		t.Fatal("project add")
	}
	writeIssueDesc(t, "PI", "x",
		"## Plan\n\n### Task 1: foo\n\n- [ ] **Step 1: a**\n")
	_, errOut, c := runCLI(t, "issue", "promote", "PI-1",
		"--task", "1", "--step", "1", "--title", "x", "--as", "bogus")
	if c == 0 {
		t.Fatal("expected non-zero exit for invalid --as")
	}
	if !strings.Contains(errOut, "invalid --as") {
		t.Fatalf("expected invalid-as error, got %q", errOut)
	}
}
```

- [ ] **Step 2: Run; expect FAIL**

```bash
go test ./internal/cli/ -run TestIssuePromote
```

- [ ] **Step 3: Add `PromoteStep` store method**

Append to `internal/store/issue.go`:
```go
type PromoteMode string

const (
	PromoteAsSubIssue PromoteMode = "sub-issue"
	PromoteAsRelated  PromoteMode = "related"
)

type PromoteParams struct {
	Parent domain.IssueKey
	TaskN  int
	StepM  int
	Title  string
	Mode   PromoteMode
}

type PromoteResult struct {
	NewKey domain.IssueKey
	Parent domain.IssueKey
	TaskN  int
	StepM  int
}

// PromoteStep creates a new issue (sub-issue or top-level w/ related_to) and
// rewrites the step line in the parent's plan to reference the new issue.
// All effects happen in a single transaction.
func (s *Store) PromoteStep(p PromoteParams) (*PromoteResult, error) {
	if p.Title == "" {
		return nil, fmt.Errorf("%w: --title required", ErrValidation)
	}
	switch p.Mode {
	case PromoteAsSubIssue, PromoteAsRelated:
	default:
		return nil, fmt.Errorf("%w: invalid --as %q (want sub-issue|related)", ErrValidation, p.Mode)
	}
	tx, err := s.db.Begin()
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInternal, err)
	}
	defer tx.Rollback()

	// 1. Read parent issue + project.
	var parentID, projID int64
	var parentDesc string
	var parentParent sql.NullInt64
	var issueSeq int64
	if err := tx.QueryRow(`SELECT i.id, i.project_id, i.description, i.parent_id, p.issue_seq FROM issue i JOIN project p ON p.id=i.project_id WHERE p.key=? AND i.seq=?`,
		p.Parent.Project, p.Parent.Seq).Scan(&parentID, &projID, &parentDesc, &parentParent, &issueSeq); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("%w: %v", ErrInternal, err)
	}
	if p.Mode == PromoteAsSubIssue && parentParent.Valid {
		return nil, fmt.Errorf("%w: cannot promote as sub-issue of a sub-issue (would exceed depth 2)", ErrValidation)
	}

	// 2. Allocate new issue seq and insert.
	newSeq := issueSeq + 1
	var maxPos sql.NullFloat64
	_ = tx.QueryRow(`SELECT MAX(position) FROM issue WHERE project_id=? AND status=?`, projID, string(domain.StatusBacklog)).Scan(&maxPos)
	pos := 1000.0
	if maxPos.Valid {
		pos = maxPos.Float64 + 1000.0
	}
	now := s.nowISO()
	var subParent any
	if p.Mode == PromoteAsSubIssue {
		subParent = parentID
	}
	res, err := tx.Exec(`INSERT INTO issue(project_id,milestone_id,parent_id,seq,title,description,status,priority,position,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)`,
		projID, nil, subParent, newSeq, p.Title, "", string(domain.StatusBacklog), string(domain.PriorityNone), pos, now, now)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInternal, err)
	}
	newID, _ := res.LastInsertId()
	if _, err := tx.Exec(`UPDATE project SET issue_seq=?, updated_at=? WHERE id=?`, newSeq, now, projID); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInternal, err)
	}

	// 3. If related mode, insert a related_to relation in BOTH directions
	// (matches AddRelation's symmetric-edge convention so future reads from
	// either side see the relation).
	if p.Mode == PromoteAsRelated {
		if _, err := tx.Exec(`INSERT OR IGNORE INTO issue_relation(from_issue_id,to_issue_id,type,created_at) VALUES(?,?,?,?)`,
			newID, parentID, "related_to", now); err != nil {
			return nil, fmt.Errorf("%w: %v", ErrInternal, err)
		}
		if _, err := tx.Exec(`INSERT OR IGNORE INTO issue_relation(from_issue_id,to_issue_id,type,created_at) VALUES(?,?,?,?)`,
			parentID, newID, "related_to", now); err != nil {
			return nil, fmt.Errorf("%w: %v", ErrInternal, err)
		}
	}

	// 4. Rewrite the parent's step line.
	step, ok := findStepForRewrite(parentDesc, p.TaskN, p.StepM)
	if !ok {
		return nil, fmt.Errorf("%w: cannot find Task %d Step %d in parent description", ErrValidation, p.TaskN, p.StepM)
	}
	newKey := domain.IssueKey{Project: p.Parent.Project, Seq: int(newSeq)}
	newLine := buildPromotedLine(step.Raw, p.Title, newKey)
	newDesc, err := descmd.RewriteStepLine(parentDesc, p.TaskN, p.StepM, newLine)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrValidation, err)
	}
	if _, err := tx.Exec(`UPDATE issue SET description=?, updated_at=? WHERE id=?`, newDesc, now, parentID); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInternal, err)
	}

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInternal, err)
	}
	return &PromoteResult{NewKey: newKey, Parent: p.Parent, TaskN: p.TaskN, StepM: p.StepM}, nil
}

// findStepForRewrite is a thin wrapper around descmd.FindSection + FindTask +
// FindStep used here to keep the existing Plan/Task/Step lookup contained.
func findStepForRewrite(desc string, taskN, stepM int) (descmd.Step, bool) {
	planStart, planEnd, ok := descmd.FindSection(desc, "Plan")
	if !ok {
		return descmd.Step{}, false
	}
	planBody := desc[planStart:planEnd]
	taskStart, taskEnd, ok := descmd.FindTask(planBody, taskN)
	if !ok {
		return descmd.Step{}, false
	}
	return descmd.FindStep(planBody[taskStart:taskEnd], stepM)
}

// buildPromotedLine produces the rewritten step line with the "→ KEY"
// suffix. If the original line already had a "→ ..." suffix, it's replaced.
func buildPromotedLine(originalLine, newTitle string, newKey domain.IssueKey) string {
	trimmed := strings.TrimRight(originalLine, "\n")
	if idx := strings.LastIndex(trimmed, " → "); idx >= 0 {
		trimmed = trimmed[:idx]
	}
	return fmt.Sprintf("%s → %s\n", trimmed, newKey.String())
}
```

- [ ] **Step 4: Add `issue promote` CLI command**

Append to `internal/cli/issue_workflow.go`:
```go
func issuePromoteCmd() *cobra.Command {
	var taskN, stepM int
	var title, asMode string
	var asJSON bool
	c := &cobra.Command{
		Use:   "promote <KEY>",
		Short: "Promote a plan step into its own issue and rewrite the step line",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			k, err := domain.ParseIssueKey(args[0])
			if err != nil {
				return err
			}
			s, err := openStore()
			if err != nil {
				return err
			}
			defer s.Close()
			res, err := s.PromoteStep(store.PromoteParams{
				Parent: k,
				TaskN:  taskN,
				StepM:  stepM,
				Title:  title,
				Mode:   store.PromoteMode(asMode),
			})
			if err != nil {
				return err
			}
			if asJSON {
				return WriteJSON(cmd.OutOrStdout(), map[string]any{
					"parent":  args[0],
					"task":    res.TaskN,
					"step":    res.StepM,
					"new_key": res.NewKey.String(),
				})
			}
			fmt.Fprintf(cmd.OutOrStdout(), "promoted %s Task %d Step %d → %s\n", args[0], res.TaskN, res.StepM, res.NewKey)
			return nil
		},
	}
	c.Flags().IntVar(&taskN, "task", 0, "task number (required, 1-indexed)")
	c.Flags().IntVar(&stepM, "step", 0, "step number (required, 1-indexed)")
	c.Flags().StringVar(&title, "title", "", "title for the promoted issue (required)")
	c.Flags().StringVar(&asMode, "as", "sub-issue", "promotion mode: sub-issue|related")
	c.Flags().BoolVar(&asJSON, "json", false, "JSON output")
	_ = c.MarkFlagRequired("task")
	_ = c.MarkFlagRequired("step")
	_ = c.MarkFlagRequired("title")
	return c
}
```

- [ ] **Step 5: Register the subcommand**

Modify `internal/cli/issue.go:20-22`:
```go
	c.AddCommand(issueAddCmd(), issueListCmd(), issueShowCmd(), issueEditCmd(), issueMvCmd(), issueRmCmd(),
		issueArchiveCmd(), issueUnarchiveCmd(), issueArchiveDoneCmd(), issueImportCmd(), issueBlockedCmd(),
		issueCurrentCmd(), issueTickCmd(), issueLogCmd(), issuePromoteCmd())
```

- [ ] **Step 6: Run tests; expect PASS**

```bash
go test ./internal/cli/ -run TestIssuePromote -v
```

- [ ] **Step 7: Commit**

```bash
git add internal/store/issue.go internal/cli/issue.go internal/cli/issue_workflow.go internal/cli/issue_workflow_test.go
git commit -m "feat(issue): add 'promote' command to split a plan step into a new issue"
```

---

## Task 11: issue show --pager

**Files:**
- Modify: `internal/cli/issue.go:481-...` (issueShowCmd)
- Test: `internal/cli/issue_cmd_test.go`

- [ ] **Step 1: Failing test for `--pager`**

Append to `internal/cli/issue_cmd_test.go`:
```go
func TestIssueShow_Pager_FallbackPlainOutput(t *testing.T) {
	// Use 'cat' as PAGER so the pipe is non-interactive and ends up on stdout.
	os.Setenv("PAGER", "cat")
	t.Cleanup(func() { os.Unsetenv("PAGER") })
	if _, _, c := runCLI(t, "init"); c != 0 {
		t.Fatal("init")
	}
	if _, _, c := runCLI(t, "project", "add", "PGR", "--name", "Pager"); c != 0 {
		t.Fatal("project add")
	}
	writeIssueDesc(t, "PGR", "showme", "## Spec\n\nbody\n")
	out, _, c := runCLI(t, "issue", "show", "PGR-1", "--pager")
	if c != 0 {
		t.Fatalf("show code=%d", c)
	}
	if !strings.Contains(out, "body") {
		t.Fatalf("expected body in piped output, got:\n%s", out)
	}
}
```

- [ ] **Step 2: Run; expect FAIL ("unknown flag --pager")**

```bash
go test ./internal/cli/ -run TestIssueShow_Pager
```

- [ ] **Step 3: Wire `--pager` into `issueShowCmd`**

Modify `internal/cli/issue.go`. Pager only wraps the human-readable (non-JSON, non-section) path; `--json` and `--section` ignore `--pager`. Replace the body of `issueShowCmd`'s `RunE` (lines 487-509) and the flag block with:

```go
		RunE: func(cmd *cobra.Command, args []string) error {
			s, err := openStore()
			if err != nil {
				return err
			}
			defer s.Close()
			k, err := domain.ParseIssueKey(args[0])
			if err != nil {
				return err
			}
			issue, err := s.GetIssueByKey(k)
			if err != nil {
				return err
			}
			// --section is mutually exclusive with --json and --pager; it's a
			// targeted machine read.
			if section != "" {
				anchor, err := sectionAnchor(section)
				if err != nil {
					return err
				}
				start, end, ok := descmd.FindSection(issue.Description, anchor)
				if !ok {
					return fmt.Errorf("%w: no ## %s section in %s", store.ErrNotFound, anchor, args[0])
				}
				fmt.Fprint(cmd.OutOrStdout(), issue.Description[start:end])
				return nil
			}
			projects := projectKeysByID(s)
			if asJSON {
				return WriteIssueJSON(cmd.OutOrStdout(), issueJSONInputs(s, projects, k.Project, issue))
			}
			parentKey, msName := resolveIssueRefs(s, projects, issue)
			body := fmt.Sprintf("%s — %s\nstatus:    %s\npriority:  %s\nmilestone: %s\nparent:    %s\n\n%s\n",
				k, issue.Title, issue.Status, issue.Priority,
				dashIfEmpty(msName), dashIfEmpty(parentKey), issue.Description)
			if usePager {
				return runPager(cmd.OutOrStdout(), []byte(body))
			}
			fmt.Fprint(cmd.OutOrStdout(), body)
			return nil
		},
	}
	c.Flags().BoolVar(&asJSON, "json", false, "JSON output")
	c.Flags().StringVar(&section, "section", "", "show only one section: spec|plan|activity|notes")
	c.Flags().BoolVar(&usePager, "pager", false, "pipe human-readable output through $PAGER")
	return c
}
```

Declare these at the top of `issueShowCmd`:
```go
	var asJSON, usePager bool
	var section string
```

Add the `runPager` helper alongside other helpers in `issue.go` (or beside `sectionAnchor` from Task 6):
```go
// runPager pipes the given bytes through $PAGER. If $PAGER is unset, falls
// back to writing directly to fallback (the command's stdout).
func runPager(fallback io.Writer, content []byte) error {
	pager := os.Getenv("PAGER")
	if pager == "" {
		_, err := fallback.Write(content)
		return err
	}
	cmd := exec.Command("sh", "-c", pager)
	cmd.Stdin = bytes.NewReader(content)
	cmd.Stdout = fallback
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
```

Add `"bytes"` and `"os/exec"` to `issue.go`'s imports if not already present. (`"io"` and `"os"` are already imported.)

Important: do not regress Task 6 — the `--section` branch in the body above MUST appear before the `asJSON` branch and before the `usePager` branch, otherwise tests from Task 6 fail.

- [ ] **Step 4: Run tests; expect PASS**

```bash
go test ./internal/cli/ -run TestIssueShow_Pager -v
```

- [ ] **Step 5: Commit**

```bash
git add internal/cli/issue.go internal/cli/issue_cmd_test.go
git commit -m "feat(issue): add --pager flag to show"
```

---

## Task 12: Document the parseable-description contract in README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read the current README to find an insertion point**

```bash
cd /home/alex/dev/cliban
grep -n "^## " README.md
```

Pick a location after the basic-usage section and before troubleshooting/contributing.

- [ ] **Step 2: Insert the contract section**

Add a new H2 section `## Description contract` to `README.md` with this content:

````markdown
## Description contract

Some cliban commands (`issue tick`, `issue promote`, `issue log`, `issue show --section`) parse the markdown structure of an issue's `description` field. They expect a small, well-defined contract:

### Top-level sections

The following H2 anchors are reserved. The exact heading text matters; cliban looks up sections by exact match.

- `## Spec` — the design/brainstorm output for this issue
- `## Plan` — the implementation plan
- `## Activity Log` — chronological events
- `## Notes` — long-lived notes (mostly for project-level descriptions)

Anything else in the description is preserved untouched.

### Plan tasks and steps

Within `## Plan`, tasks are numbered H3 headings:

```markdown
## Plan

### Task 1: short title

- [ ] **Step 1: ...**
- [ ] **Step 2: ...**

### Task 2: another short title

- [ ] **Step 1: ...**
```

- Tasks are numbered (`### Task <N>:`). Numbers must be unique within the section.
- Steps are GFM checkbox lines at column zero: `- [ ] ...` or `- [x] ...`. Indented child bullets are not parsed as steps.

### Promotion suffix

A step that has been split into its own issue is suffixed with ` → KEY`:

```markdown
- [ ] **Step 3: CSRF middleware** → CLI-18
```

This is produced by `cliban issue promote` and consumed by readers (humans, and any tooling that walks plans).

### Failure mode

If the description structure is violated (missing `## Plan` anchor, renamed `### Task N`, etc.), the workflow commands exit with code 2 and a clear error pointing at the structural problem. No best-effort recovery — fix the description and retry.
````

- [ ] **Step 3: Verify the README still renders**

```bash
go test ./...   # belt-and-suspenders sanity check
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: describe the parseable-description contract"
```

---

## Verification After All Tasks

- [ ] **Step 1: Run the full test suite**

```bash
cd /home/alex/dev/cliban
go test ./...
```

Expected: all tests pass.

- [ ] **Step 2: Smoke-test the new commands against a real DB**

```bash
TMPDB=$(mktemp /tmp/cliban-smoke-XXXX.db)
export CLIBAN_DB="$TMPDB"
cliban init
cliban project add SMK --name "Smoke"
cliban milestone add --project SMK --name v0.1 --description-file - <<'EOF'
## Spec

smoke milestone
EOF
cliban issue add --project SMK --title "smoke test" --description-file - <<'EOF'
## Spec

smoke spec

## Plan

### Task 1: do something

- [ ] **Step 1: write test**
- [ ] **Step 2: implement**
EOF
cliban issue tick SMK-1 --task 1 --step 1 --json
cliban issue log SMK-1 "smoke test passed" --json
cliban issue promote SMK-1 --task 1 --step 2 --title "implement (promoted)" --as sub-issue --json
cliban issue show SMK-1 --section plan
cliban issue show SMK-1 --section activity
cliban issue ls --project SMK --updated-since 1h --json
git init /tmp/cliban-smoke-repo 2>/dev/null || true
(cd /tmp/cliban-smoke-repo && git checkout -b smk-1-smoke-test 2>/dev/null && CLIBAN_CURRENT_BRANCH_OVERRIDE=smk-1-smoke-test cliban issue current --json)
rm -f "$TMPDB"
```

Expected: every step prints either a JSON object or the requested section content; no errors.

- [ ] **Step 3: Tag a release (optional)**

If happy with the smoke test, bump the version and tag:

```bash
git tag -a v$(date +%Y.%m.%d) -m "cliban workflow extensions"
```
