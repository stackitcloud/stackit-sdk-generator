package main

import "testing"

func TestLanguageNormalizeServiceName(t *testing.T) {
	tests := []struct {
		language string
		service  string
		want     string
	}{
		{language: "go", service: "Foo-_ Bar!", want: "foobar"},
		{language: "python", service: "Foo-_ Bar!", want: "foobar"},
		{language: "java", service: "Foo-_ Bar!", want: "foobar"},
		{language: "java", service: "123-service", want: "_123service"},
	}

	for _, test := range tests {
		t.Run(test.language+"/"+test.service, func(t *testing.T) {
			language, err := newLanguage(test.language)
			if err != nil {
				t.Fatal(err)
			}
			if got := language.NormalizeServiceName(test.service); got != test.want {
				t.Errorf("NormalizeServiceName(%q) = %q, want %q", test.service, got, test.want)
			}
		})
	}
}
