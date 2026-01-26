#!/usr/bin/env python3
"""
Mock HTTP sink that simulates authentication errors.

This server accepts POST requests and:
- Returns 200 OK if Authorization header is "Bearer valid-token"
- Returns 401 Unauthorized if Authorization header is "Bearer invalid-token"
- Returns 400 Bad Request for any other Authorization header
- Logs all received events to stdout
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import sys
from datetime import datetime

class MockSinkHandler(BaseHTTPRequestHandler):
    # Class variable to track received events
    received_events = []
    
    def do_POST(self):
        # Read the request body
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        
        # Get authorization header
        auth_header = self.headers.get('Authorization', '')
        
        # Parse the body (assuming JSON array or single JSON object)
        try:
            if body:
                data = json.loads(body)
                if isinstance(data, list):
                    event_count = len(data)
                else:
                    event_count = 1
                    data = [data]
            else:
                event_count = 0
                data = []
        except json.JSONDecodeError:
            event_count = 0
            data = []
        
        timestamp = datetime.now().isoformat()
        
        # Check authorization and respond accordingly
        if auth_header == "Bearer valid-token":
            # Success case
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            response = {"status": "success", "received": event_count}
            self.wfile.write(json.dumps(response).encode())
            
            # Log to stdout
            print(f"[{timestamp}] ✅ SUCCESS: Received {event_count} events with valid token", flush=True)
            for i, event in enumerate(data):
                MockSinkHandler.received_events.append(event)
                print(f"  Event {len(MockSinkHandler.received_events)}: {json.dumps(event)}", flush=True)
                
        elif auth_header == "Bearer invalid-token":
            # Authentication error case
            self.send_response(401)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            response = {"error": "Unauthorized", "message": "Invalid authentication token"}
            self.wfile.write(json.dumps(response).encode())
            
            # Log to stdout
            print(f"[{timestamp}] ❌ REJECTED: {event_count} events with invalid token (401 Unauthorized)", flush=True)
            for event in data:
                print(f"  Rejected: {json.dumps(event)}", flush=True)
                
        else:
            # Bad request case
            self.send_response(400)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            response = {"error": "Bad Request", "message": "Missing or invalid Authorization header"}
            self.wfile.write(json.dumps(response).encode())
            
            # Log to stdout
            print(f"[{timestamp}] ⚠️  BAD REQUEST: {event_count} events with invalid auth header", flush=True)
    
    def do_GET(self):
        """Health check and stats endpoint"""
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            response = {"status": "healthy"}
            self.wfile.write(json.dumps(response).encode())
        elif self.path == '/stats':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            response = {
                "total_received": len(MockSinkHandler.received_events),
                "events": MockSinkHandler.received_events
            }
            self.wfile.write(json.dumps(response).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        # Suppress default HTTP server logs
        pass

def run_server(port=8080):
    server_address = ('', port)
    httpd = HTTPServer(server_address, MockSinkHandler)
    print(f"Mock sink server starting on port {port}...", flush=True)
    print(f"  - Valid token: 'Bearer valid-token' -> 200 OK", flush=True)
    print(f"  - Invalid token: 'Bearer invalid-token' -> 401 Unauthorized", flush=True)
    print(f"  - Health check: GET /health", flush=True)
    print(f"  - Stats: GET /stats", flush=True)
    print("", flush=True)
    httpd.serve_forever()

if __name__ == '__main__':
    run_server()

