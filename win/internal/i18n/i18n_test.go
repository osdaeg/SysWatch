package i18n

import (
	"strings"
	"testing"
)

func TestPairsCaseInsensitiveLanguageCode(t *testing.T) {
	tr := &Translator{data: map[string]map[string]string{}}
	tr.Load(strings.NewReader("en=Download\nEs=Descarga\r\nen=Upload\nes=Subida\n"))
	tr.SetLang("es-AR")
	if tr.T("Download") != "Descarga" || tr.T("Upload") != "Subida" {
		t.Error("translation failed")
	}
	if tr.T("Unknown text") != "Unknown text" {
		t.Error("missing entry must fall back to English")
	}
	tr.SetLang("en")
	if tr.T("Download") != "Download" {
		t.Error("en must not translate")
	}
}

func TestEmbeddedSpanish(t *testing.T) {
	tr := New()
	tr.SetLang("es")
	if tr.T("Cores") != "Núcleos" || tr.T("Estimated load: 1 minute") != "Carga estimada: 1 minuto" {
		t.Error("embedded es.conf not loaded")
	}
}
