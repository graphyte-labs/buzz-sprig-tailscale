// mcp-legacy-proxy keeps Goose on the MCP initialize handshake when it talks to
// a server that only accepts that handshake.
//
// Goose (rmcp 3.x) opens a streamable-HTTP connection with `server/discover`.
// A server that answers it with only pre-2026-07-28 versions gets the oldest
// one it lists, but rmcp then sends session-less requests with per-request
// `_meta` keys, which such a server refuses with JSON-RPC -32022. rmcp falls
// back to `initialize` when `server/discover` is rejected with a 4xx, so this
// proxy answers every `server/discover` POST with 404 and -32601 and forwards
// everything else unchanged.
//
// It listens on 127.0.0.1 only. Upstream requests honour HTTPS_PROXY, so they
// reach the tailnet through tailscaled like the agent's own calls.
package main

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"time"
)

// Larger request bodies are forwarded without being inspected.
const maxInspect = 1 << 20

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	listen := os.Getenv("MCP_LEGACY_PROXY_LISTEN")
	if listen == "" {
		listen = "127.0.0.1:8765"
	}
	upstream, err := url.Parse(os.Getenv("MCP_LEGACY_PROXY_UPSTREAM"))
	if err != nil || upstream.Scheme != "https" || upstream.Host == "" {
		log.Error("MCP_LEGACY_PROXY_UPSTREAM must be an https:// origin", "value", os.Getenv("MCP_LEGACY_PROXY_UPSTREAM"))
		os.Exit(1)
	}

	proxy := httputil.NewSingleHostReverseProxy(upstream)
	proxy.Transport = &http.Transport{Proxy: http.ProxyFromEnvironment, ForceAttemptHTTP2: true}
	// Flush SSE events as they arrive.
	proxy.FlushInterval = -1
	director := proxy.Director
	proxy.Director = func(r *http.Request) {
		director(r)
		r.Host = upstream.Host
	}

	server := &http.Server{
		Addr:              listen,
		ReadHeaderTimeout: 10 * time.Second,
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Method == http.MethodPost && r.Header.Get("Mcp-Session-Id") == "" {
				body, err := io.ReadAll(io.LimitReader(r.Body, maxInspect+1))
				r.Body.Close()
				if err != nil {
					http.Error(w, "read request body", http.StatusBadRequest)
					return
				}
				if len(body) <= maxInspect {
					if id, ok := discoverID(body); ok {
						log.Info("refused server/discover", "path", r.URL.Path)
						refuse(w, id)
						return
					}
				}
				r.Body = io.NopCloser(bytes.NewReader(body))
				r.ContentLength = int64(len(body))
			}
			proxy.ServeHTTP(w, r)
		}),
	}
	log.Info("listening", "addr", listen, "upstream", upstream.String())
	if err := server.ListenAndServe(); err != nil {
		log.Error("stopped", "error", err)
		os.Exit(1)
	}
}

// discoverID reports whether body is a single `server/discover` request, and
// returns its id.
func discoverID(body []byte) (json.RawMessage, bool) {
	var request struct {
		ID     json.RawMessage `json:"id"`
		Method string          `json:"method"`
	}
	if json.Unmarshal(body, &request) != nil || request.Method != "server/discover" {
		return nil, false
	}
	return request.ID, true
}

// refuse answers as a server without `server/discover` would. rmcp treats a
// 4xx JSON-RPC error to it as a legacy server and sends `initialize` instead.
func refuse(w http.ResponseWriter, id json.RawMessage) {
	if len(id) == 0 {
		id = json.RawMessage("null")
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusNotFound)
	json.NewEncoder(w).Encode(map[string]any{
		"jsonrpc": "2.0",
		"id":      id,
		"error":   map[string]any{"code": -32601, "message": "Method not found: server/discover"},
	})
}
