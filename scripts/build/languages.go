package main

import (
	"fmt"
	"strings"
)

type Language interface {
	NormalizeServiceName(string) string
}

type goLanguage struct{}

func (goLanguage) NormalizeServiceName(service string) string {
	return normalizeAlphaNumeric(service)
}

type pythonLanguage struct{}

func (pythonLanguage) NormalizeServiceName(service string) string {
	return normalizeAlphaNumeric(service)
}

type javaLanguage struct{}

func (javaLanguage) NormalizeServiceName(service string) string {
	name := normalizeAlphaNumeric(service)
	if name != "" && name[0] >= '0' && name[0] <= '9' {
		return "_" + name
	}
	return name
}

func newLanguage(name string) (Language, error) {
	switch name {
	case "go":
		return goLanguage{}, nil
	case "python":
		return pythonLanguage{}, nil
	case "java":
		return javaLanguage{}, nil
	default:
		return nil, fmt.Errorf("unsupported language %q", name)
	}
}

func normalizeAlphaNumeric(service string) string {
	var normalized strings.Builder
	for _, char := range strings.ToLower(service) {
		if (char >= 'a' && char <= 'z') || (char >= '0' && char <= '9') {
			normalized.WriteRune(char)
		}
	}
	return normalized.String()
}
