import os
import sys
import json
import socketserver
from http.server import SimpleHTTPRequestHandler
import urllib.parse

# Add parent directory to path so we can import scanner and linker easily
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import scanner
import linker

PORT = 8085
if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
    FRONTEND_DIR = os.path.join(sys._MEIPASS, "frontend")
else:
    FRONTEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "frontend"))

class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    # Allow instant binding without waiting for socket time_wait to clear
    allow_reuse_address = True

class SymLinkrAPIHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        # Initialize with frontend directory as root for static serving
        super().__init__(*args, directory=FRONTEND_DIR, **kwargs)

    def end_headers(self):
        # Add CORS headers for local development testing convenience
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        parsed_path = urllib.parse.urlparse(self.path)
        path = parsed_path.path

        if path.startswith("/api/"):
            self.handle_api_get(path, parsed_path.query)
        else:
            # Serve static files normally
            super().do_GET()

    def do_POST(self):
        parsed_path = urllib.parse.urlparse(self.path)
        path = parsed_path.path

        if path.startswith("/api/"):
            # Read POST body
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length).decode('utf-8')
            try:
                data = json.loads(post_data) if post_data else {}
            except json.JSONDecodeError:
                data = {}
            
            self.handle_api_post(path, data)
        else:
            self.send_error(404, "Not Found")

    def send_json(self, status_code, data):
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))

    def handle_api_get(self, path, query_string):
        query_params = urllib.parse.parse_qs(query_string)
        
        if path == "/api/status":
            try:
                prefixes = scanner.get_wine_prefixes()
                # Get drive stats for home directory
                home_stat = os.statvfs(os.path.expanduser("~"))
                free_space_gb = (home_stat.f_bavail * home_stat.f_frsize) / (1024**3)
                
                self.send_json(200, {
                    "status": "online",
                    "os": sys.platform,
                    "wine_prefixes": prefixes,
                    "free_space_gb": round(free_space_gb, 2),
                    "default_linux_paths": scanner.LINUX_PLUGIN_PATHS
                })
            except Exception as e:
                self.send_json(500, {"error": str(e)})

        elif path == "/api/plugins":
            # Direct quick scan
            try:
                native = scanner.scan_native_plugins()
                wine_plugins = []
                for prefix in scanner.get_wine_prefixes():
                    wine_plugins.extend(scanner.scan_wine_plugins(prefix))
                
                self.send_json(200, {
                    "native": native,
                    "wine": wine_plugins,
                    "total": len(native) + len(wine_plugins)
                })
            except Exception as e:
                self.send_json(500, {"error": str(e)})
        else:
            self.send_json(404, {"error": f"API endpoint GET {path} not found"})

    def handle_api_post(self, path, data):
        if path == "/api/scan":
            prefix = data.get("wine_prefix")
            try:
                native = scanner.scan_native_plugins()
                wine_plugins = []
                if prefix:
                    wine_plugins = scanner.scan_wine_plugins(prefix)
                else:
                    for p in scanner.get_wine_prefixes():
                        wine_plugins.extend(scanner.scan_wine_plugins(p))
                
                self.send_json(200, {
                    "native": native,
                    "wine": wine_plugins,
                    "total": len(native) + len(wine_plugins)
                })
            except Exception as e:
                self.send_json(500, {"error": str(e)})

        elif path == "/api/resources":
            plugin_name = data.get("name")
            is_wine = data.get("type") == "wine"
            prefix = data.get("prefix")
            
            if not plugin_name:
                self.send_json(400, {"error": "Missing parameter 'name'"})
                return
                
            try:
                suggestions = scanner.find_associated_resources(plugin_name, is_wine, prefix)
                self.send_json(200, {"suggestions": suggestions})
            except Exception as e:
                self.send_json(500, {"error": str(e)})

        elif path == "/api/profile/create":
            name = data.get("name")
            plugin_format = data.get("format")
            plugin_type = data.get("type") # native or wine
            main_path = data.get("path")
            resources = data.get("resources", [])
            target_dir = data.get("target_dir")
            strategy = data.get("strategy", "symlink")
            registry_keys = data.get("registry_keys", [])
            wine_prefix = data.get("prefix")
            
            if not name or not main_path or not target_dir:
                self.send_json(400, {"error": "Missing required fields (name, path, target_dir)"})
                return
                
            try:
                manifest = linker.package_plugin(
                    name=name,
                    plugin_format=plugin_format,
                    plugin_type=plugin_type,
                    main_plugin_path=main_path,
                    resource_paths=resources,
                    target_dir=target_dir,
                    strategy=strategy,
                    registry_keys=registry_keys,
                    wine_prefix=wine_prefix
                )
                self.send_json(200, {"success": True, "manifest": manifest})
            except Exception as e:
                self.send_json(500, {"error": str(e)})

        elif path == "/api/profile/apply":
            portable_dir = data.get("portable_dir")
            strategy = data.get("strategy") # Override manifest strategy if provided
            
            if not portable_dir:
                self.send_json(400, {"error": "Missing parameter 'portable_dir'"})
                return
                
            try:
                manifest = linker.apply_profile(portable_dir, strategy)
                self.send_json(200, {"success": True, "manifest": manifest})
            except Exception as e:
                self.send_json(500, {"error": str(e)})

        elif path == "/api/profile/unlink":
            portable_dir = data.get("portable_dir")
            
            if not portable_dir:
                self.send_json(400, {"error": "Missing parameter 'portable_dir'"})
                return
                
            try:
                unlinked = linker.remove_profile(portable_dir)
                self.send_json(200, {"success": True, "unlinked_count": unlinked})
            except Exception as e:
                self.send_json(500, {"error": str(e)})

        elif path == "/api/profile/health":
            portable_dir = data.get("portable_dir")
            
            if not portable_dir:
                self.send_json(400, {"error": "Missing parameter 'portable_dir'"})
                return
                
            try:
                health = linker.check_profile_health(portable_dir)
                self.send_json(200, health)
            except Exception as e:
                self.send_json(500, {"error": str(e)})

        elif path == "/api/profile/scan_portable":
            root_dir = data.get("root_dir")
            if not root_dir or not os.path.exists(root_dir):
                self.send_json(400, {"error": "Invalid or missing 'root_dir'"})
                return
                
            try:
                profiles = []
                for dirpath, dirnames, filenames in os.walk(root_dir):
                    if "symlinkr.json" in filenames:
                        manifest_path = os.path.join(dirpath, "symlinkr.json")
                        try:
                            with open(manifest_path, "r") as f:
                                manifest = json.load(f)
                            profiles.append({
                                "name": manifest.get("name"),
                                "format": manifest.get("format"),
                                "type": manifest.get("type"),
                                "portable_dir": dirpath,
                                "health": linker.check_profile_health(dirpath)
                            })
                        except Exception:
                            pass
                self.send_json(200, {"profiles": profiles})
            except Exception as e:
                self.send_json(500, {"error": str(e)})
        else:
            self.send_json(404, {"error": f"API endpoint POST {path} not found"})

def run_server():
    # Make sure frontend folder exists
    os.makedirs(FRONTEND_DIR, exist_ok=True)
    
    server_address = ('', PORT)
    httpd = ThreadedTCPServer(server_address, SymLinkrAPIHandler)
    print(f"🚀 SymLinkr Backend server running on http://localhost:{PORT}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping server...")
        httpd.shutdown()

if __name__ == '__main__':
    run_server()
