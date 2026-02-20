# CLAUDE.md

This file provides guidance for AI assistants working in this repository.

## Project Overview

This is a Go project in early initialization. Currently the repository contains only foundational scaffolding (`.gitignore`, `README.md`). No source code, modules, tests, or build infrastructure have been implemented yet.

**Language**: Go
**Repository**: `ryo12-n/work`
**Branch model**: feature branches off `master`/`main`

---

## Repository Structure

```
/
├── .gitignore       # Go-specific ignore rules
├── README.md        # Project title placeholder
└── CLAUDE.md        # This file
```

As the project grows, the expected Go project layout is:

```
/
├── cmd/             # Main application entry points (one subdir per binary)
│   └── <app>/
│       └── main.go
├── internal/        # Private application/library code (not importable externally)
├── pkg/             # Public library code (importable by external projects)
├── api/             # API definitions (OpenAPI specs, protobuf files, etc.)
├── configs/         # Configuration file templates
├── scripts/         # Build and maintenance scripts
├── docs/            # Project documentation
├── go.mod           # Go module definition
├── go.sum           # Dependency checksums
├── Makefile         # Build targets
└── CLAUDE.md        # This file
```

---

## Development Setup

### Prerequisites

- Go 1.21+ (`go version` to verify)
- Git with GPG signing configured (commits in this repo are GPG-signed)

### Initialize the Go module

When creating the module for the first time:

```bash
go mod init github.com/ryo12-n/work
```

### Install dependencies

```bash
go mod tidy
```

### Build

```bash
go build ./...
```

### Run

```bash
go run ./cmd/<app>/
```

---

## Testing

This project uses the standard Go test toolchain.

### Run all tests

```bash
go test ./...
```

### Run tests with coverage

```bash
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out
```

### Run a specific test

```bash
go test -run TestFunctionName ./path/to/package/
```

### Test conventions

- Test files are named `<file>_test.go` in the same package as the code under test
- Use `package foo_test` (external test package) for black-box tests
- Use `package foo` (same package) for white-box tests that need access to unexported symbols
- Table-driven tests are preferred for comprehensive coverage
- Subtests (`t.Run(...)`) should be used to group related cases

---

## Code Conventions

### General Go style

- Follow [Effective Go](https://go.dev/doc/effective_go) and the [Go Code Review Comments](https://github.com/golang/go/wiki/CodeReviewComments)
- Use `gofmt` / `goimports` for formatting — never commit unformatted code
- Run `go vet ./...` before committing
- Prefer `errors.Is` / `errors.As` over string matching for error checks
- Return errors; do not use `panic` in library code
- Keep functions small and focused on a single responsibility

### Naming

- Packages: lowercase single words, no underscores (`httputil`, not `http_util`)
- Exported identifiers: PascalCase; unexported: camelCase
- Interfaces: use `-er` suffix when possible (`Reader`, `Writer`, `Stringer`)
- Avoid stutter: `user.User` should just be `user.T` or restructure the package

### Error handling

- Wrap errors with context: `fmt.Errorf("loading config: %w", err)`
- Define sentinel errors as package-level vars: `var ErrNotFound = errors.New("not found")`
- Return `(T, error)` pairs; avoid out-parameters

### Comments

- Every exported symbol must have a doc comment starting with the symbol name
- Comments are full sentences ending with a period
- Use `// TODO(username): ...` for tracked work items

---

## Git Workflow

### Branch naming

- Feature branches: `feature/<short-description>`
- Bug fixes: `fix/<short-description>`
- Claude-generated branches follow: `claude/<description>-<session-id>`

### Commit messages

Use the conventional commit format:

```
<type>(<scope>): <short summary>

<body — optional, wrap at 72 chars>

<footer — optional, e.g. Closes #123>
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`

Example:

```
feat(api): add user registration endpoint

Implements POST /users with email/password validation.
Passwords are hashed with bcrypt (cost 12).

Closes #42
```

### Commit hygiene

- Commits are GPG-signed in this repository; ensure signing is configured
- Keep commits atomic — one logical change per commit
- Do not commit `.env` files, test binaries, or build artifacts (covered by `.gitignore`)

---

## Linting and Static Analysis

When a linter configuration is added, the recommended tools are:

```bash
# Format and organize imports
goimports -w .

# Vet
go vet ./...

# golangci-lint (aggregates many linters)
golangci-lint run ./...
```

A `.golangci.yml` should be added at the root when the project matures.

---

## CI/CD

No CI pipeline is configured yet. When added, the pipeline should:

1. Run `go build ./...`
2. Run `go vet ./...`
3. Run `go test -race -coverprofile=coverage.out ./...`
4. Upload coverage report
5. Run `golangci-lint run ./...`

---

## Environment Variables

- Never commit `.env` files (already in `.gitignore`)
- Document all required environment variables in a `.env.example` file
- Prefer structured configuration with validation at startup (e.g., via `github.com/caarlos0/env` or `github.com/spf13/viper`)

---

## AI Assistant Guidelines

### What to do

- Read existing code before modifying it — never guess at structure
- Follow Go idioms and the conventions in this file
- Prefer editing existing files over creating new ones
- Keep changes minimal and scoped to what was requested
- Run `go build ./...` and `go vet ./...` after making changes
- Run `go test ./...` to verify nothing is broken
- Use `goimports` to format changed files

### What to avoid

- Do not commit vendored dependencies without explicit instruction
- Do not add dependencies without justification — evaluate stdlib alternatives first
- Do not add global state or `init()` functions without a clear reason
- Do not use `interface{}` / `any` when a concrete type is known
- Do not suppress errors with `_`
- Do not add `TODO` comments without an owner/issue reference

### When uncertain

- Ask before introducing a new dependency
- Ask before restructuring packages or changing public APIs
- Prefer conservative, minimal changes when requirements are ambiguous
