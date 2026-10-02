// parse-buffer-lab reproduces the Go http.ReadResponse failures seen in OBI v0.11.0 DEBUG
// when the response large buffer is misaligned (issue #3578, @mmat11 comment 5931550365).
//
// Run: go run ./cmd/parse-buffer-lab
//
// This does not use eBPF; it shows why HTTPInfoEventToSpan falls back when respErr is set.
package main

import (
	"bufio"
	"bytes"
	"fmt"
	"net/http"
)

func parseResponse(label string, raw []byte) {
	req, _ := http.NewRequest("GET", "/", nil)
	rd := bufio.NewReader(bytes.NewReader(raw))
	_, err := http.ReadResponse(rd, req)
	if err != nil {
		fmt.Printf("OK %s: respErr=%q\n", label, err.Error())
		return
	}
	fmt.Printf("UNEXPECTED %s: parse succeeded\n", label)
}

func main() {
	fmt.Println("=== Response buffers that fail http.ReadResponse (same helper as OBI httpSafeParseResponse) ===")
	fmt.Println()

	// Sanitized cluster DEBUG (2026-10-01):
	// respErr="malformed MIME header line: \" \""
	parseResponse("cluster-A_space_header_line", []byte("HTTP/1.1 200 OK\r\n \r\nContent-Length: 0\r\n\r\n"))

	// respErr="malformed MIME header: missing colon: \"0\""
	parseResponse("cluster-B_body_byte_as_header", []byte("HTTP/1.1 200 OK\r\nContent-Length: 1\r\n0"))
	parseResponse("cluster-B_variant_header_line_0", []byte("HTTP/1.1 200 OK\r\n0\r\nContent-Length: 0\r\n\r\n"))

	// Valid baseline (enrichment path can run when both req+resp parse).
	parseResponse("valid_small_json", []byte("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}"))
}
