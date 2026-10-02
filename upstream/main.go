// Upstream HTTP server for OBI #3578 docker-compose repro (no app-level tracing).
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

func main() {
	mux := http.NewServeMux()

	mux.HandleFunc("/small", handleSmall)
	mux.HandleFunc("/large", handleLarge)
	mux.HandleFunc("/chunked", handleChunked)
	mux.HandleFunc("/html", handleHTML)
	mux.HandleFunc("/appshell-like", handleAppshellLike)
	mux.HandleFunc("/", handleAppshellLike)

	// 8080 in bridge compose; 18080 when upstream uses host networking with nginx-host.conf.
	addr := ":8080"
	if p := os.Getenv("LISTEN_ADDR"); p != "" {
		addr = p
	}
	log.Printf("upstream listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}

func handleSmall(w http.ResponseWriter, r *http.Request) {
	time.Sleep(50 * time.Millisecond)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{
		"path":   r.URL.Path,
		"method": r.Method,
	})
}

func handleLarge(w http.ResponseWriter, r *http.Request) {
	// Default 16 KiB — above typical OBI http buffer_sizes (8192) when fully captured.
	kb, _ := strconv.Atoi(r.URL.Query().Get("kb"))
	if kb <= 0 {
		kb = 16
	}
	payload := strings.Repeat("x", kb*1024)
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("X-Payload-Kb", strconv.Itoa(kb))
	_, _ = fmt.Fprint(w, payload)
}

func handleChunked(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	w.Header().Set("Transfer-Encoding", "chunked")
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "no flush", http.StatusInternalServerError)
		return
	}
	for i := 0; i < 8; i++ {
		_, _ = fmt.Fprintf(w, "chunk-%d\n", i)
		flusher.Flush()
		time.Sleep(40 * time.Millisecond)
	}
}

// handleAppshellLike approximates www-web GET / via openresty → app-shell (see fixtures/curl-get-root.sanitized.txt).
func handleAppshellLike(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Vary", "Accept-Encoding")
	w.Header().Set("accept-ch", "Sec-CH-Viewport-Width")
	w.Header().Set("critical-ch", "Sec-CH-Viewport-Width")
	w.Header().Set("x-middleware-rewrite", "/")
	w.Header().Set("Cache-Control", "private, no-cache, no-store, max-age=0, must-revalidate")
	w.Header().Set("ETag", `"repro-3578"`)
	http.SetCookie(w, &http.Cookie{Name: "ptv_jwt_refresh", Value: "28800", Path: "/", SameSite: http.SameSiteLaxMode})
	http.SetCookie(w, &http.Cookie{Name: "ptv_session_id", Value: "repro-session", Path: "/", SameSite: http.SameSiteLaxMode})
	bodyKB, _ := strconv.Atoi(r.URL.Query().Get("kb"))
	if bodyKB <= 0 {
		bodyKB = 392 // ~401965 bytes HTML payload observed on dev www-web
	}
	pad := strings.Repeat("x", bodyKB*1024)
	_, _ = fmt.Fprintf(w, "<!DOCTYPE html><html><head><title>repro</title></head><body>%s</body></html>", pad)
}

func handleHTML(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	http.SetCookie(w, &http.Cookie{Name: "session", Value: "repro-session", Path: "/"})
	http.SetCookie(w, &http.Cookie{Name: "pref", Value: "en-US", Path: "/"})
	_, _ = fmt.Fprintf(w, "<!doctype html><html><body><h1>%s</h1></body></html>\n", r.URL.Path)
}
