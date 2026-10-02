// Upstream HTTP server for OBI #3578 docker-compose repro (no app-level tracing).
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
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
	mux.HandleFunc("/", handleSmall)

	addr := ":8080"
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

func handleHTML(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	http.SetCookie(w, &http.Cookie{Name: "session", Value: "repro-session", Path: "/"})
	http.SetCookie(w, &http.Cookie{Name: "pref", Value: "en-US", Path: "/"})
	_, _ = fmt.Fprintf(w, "<!doctype html><html><body><h1>%s</h1></body></html>\n", r.URL.Path)
}
