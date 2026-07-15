import os
import sys
import shutil
import json
import subprocess

def create_safe_symlink(src, dest, strategy="symlink"):
    """
    Creates a link from src pointing to dest.
    If src already exists, it is backed up or removed if it's already a link.
    On Windows, if symlinking fails due to permissions (Developer Mode off/Non-Admin),
    it falls back to a Directory Junction (for folders) or a Hard Link (for files).
    """
    src = os.path.abspath(src)
    dest = os.path.abspath(dest)

    if not os.path.exists(dest):
        raise FileNotFoundError(f"Destination path does not exist: {dest}")

    # Create parent directory of src if it doesn't exist
    os.makedirs(os.path.dirname(src), exist_ok=True)

    # Clean up existing source path if it exists
    if os.path.exists(src) or os.path.islink(src):
        if os.path.islink(src):
            try:
                os.unlink(src)
            except OSError:
                # Windows might require rmdir for directory junctions
                if os.path.isdir(src):
                    os.rmdir(src)
                else:
                    os.unlink(src)
        elif os.path.isdir(src):
            backup_path = f"{src}.bak"
            if os.path.exists(backup_path):
                shutil.rmtree(backup_path) if os.path.isdir(backup_path) else os.remove(backup_path)
            shutil.move(src, backup_path)
        else:
            backup_path = f"{src}.bak"
            if os.path.exists(backup_path):
                os.remove(backup_path)
            shutil.move(src, backup_path)

    is_dir = os.path.isdir(dest)

    # Apply linking strategy
    if sys.platform == "win32":
        if strategy == "hardlink" and not is_dir:
            try:
                os.link(dest, src)
                return
            except OSError:
                pass # Fallback if cross-drive hardlink
                
        # Try symbolic link first
        try:
            os.symlink(dest, src, target_is_directory=is_dir)
        except OSError:
            # Fallback for Windows without Admin/Developer Mode
            if is_dir:
                # Create Directory Junction (works without admin rights!)
                # cmd /c mklink /j "src" "dest"
                cmd = f'cmd /c mklink /j "{src}" "{dest}"'
                subprocess.run(cmd, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            else:
                # Fallback to Hard Link for files if symlink fails
                try:
                    os.link(dest, src)
                except OSError:
                    # Final fallback: copy file if cross-drive and link fails
                    shutil.copy2(dest, src)
    else:
        # Linux/macOS
        if strategy == "hardlink" and not is_dir:
            os.link(dest, src)
        else:
            os.symlink(dest, src)

def remove_symlink(src):
    """Safely remove a symlink or junction without touching the target files."""
    if os.path.islink(src) or (sys.platform == "win32" and os.path.exists(src)):
        try:
            if os.path.islink(src):
                os.unlink(src)
            elif os.path.isdir(src):
                # Directory Junction on Windows is seen as directory, remove via rmdir
                os.rmdir(src)
            else:
                os.unlink(src)
            return True
        except Exception:
            pass
    return False

def export_registry(reg_key, output_file, prefix=None):
    """
    Exports a registry key to a .reg file.
    Supports Windows natively (using reg.exe) and Linux Wine (using wine regedit).
    """
    if sys.platform == "win32":
        # Native Windows: reg export "Key" "file.reg" /y
        cmd = ["reg", "export", reg_key, output_file, "/y"]
        try:
            subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
            return os.path.exists(output_file)
        except Exception as e:
            print(f"Failed to export native Windows registry key {reg_key}: {e}")
            return False
    else:
        # Wine on Linux
        if not prefix or not os.path.exists(prefix):
            return False
            
        cmd = ["wine", "regedit", "/e", output_file, reg_key]
        env = os.environ.copy()
        env["WINEPREFIX"] = prefix
        
        try:
            subprocess.run(cmd, env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
            return os.path.exists(output_file)
        except Exception as e:
            print(f"Failed to export Wine registry key {reg_key}: {e}")
            return False

def import_registry(reg_file, prefix=None):
    """
    Imports a .reg file.
    Supports Windows natively and Linux Wine.
    """
    if not os.path.exists(reg_file):
        return False

    if sys.platform == "win32":
        # Native Windows: reg import "file.reg"
        cmd = ["reg", "import", reg_file]
        try:
            subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
            return True
        except Exception as e:
            print(f"Failed to import native Windows registry file {reg_file}: {e}")
            return False
    else:
        # Wine on Linux
        if not prefix or not os.path.exists(prefix):
            return False
            
        cmd = ["wine", "regedit", reg_file]
        env = os.environ.copy()
        env["WINEPREFIX"] = prefix
        
        try:
            subprocess.run(cmd, env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
            return True
        except Exception as e:
            print(f"Failed to import Wine registry file {reg_file}: {e}")
            return False

def package_plugin(name, plugin_format, plugin_type, main_plugin_path, resource_paths, target_dir, strategy="symlink", registry_keys=None, wine_prefix=None):
    """
    Packages a plugin by moving its binaries and data files to a central target folder,
    creating the symlink/junction structure, and exporting registry details.
    """
    target_dir = os.path.abspath(target_dir)
    os.makedirs(target_dir, exist_ok=True)
    
    manifest = {
        "name": name,
        "format": plugin_format,
        "type": plugin_type,
        "wine_prefix": wine_prefix,
        "strategy": strategy,
        "links": [],
        "registry": []
    }
    
    # 1. Package the main plugin binary/bundle
    main_name = os.path.basename(main_plugin_path)
    portable_main_dir = os.path.join(target_dir, "binaries")
    os.makedirs(portable_main_dir, exist_ok=True)
    
    portable_main_path = os.path.join(portable_main_dir, main_name)
    
    # Move main binary/bundle to target_dir
    print(f"Moving main plugin from {main_plugin_path} to {portable_main_path}")
    if os.path.isdir(main_plugin_path):
        shutil.copytree(main_plugin_path, portable_main_path, symlinks=True)
        shutil.rmtree(main_plugin_path)
    else:
        shutil.copy2(main_plugin_path, portable_main_path)
        os.remove(main_plugin_path)
        
    manifest["links"].append({
        "src": main_plugin_path,
        "dest": os.path.join("binaries", main_name),
        "is_dir": os.path.isdir(portable_main_path)
    })
    
    # 2. Package other resource paths (AppData, Documents, etc.)
    for idx, path in enumerate(resource_paths):
        if not os.path.exists(path):
            continue
            
        path_name = os.path.basename(path)
        dest_subdir = f"resource_{idx}_{path_name}"
        portable_res_path = os.path.join(target_dir, dest_subdir)
        
        print(f"Moving resource folder from {path} to {portable_res_path}")
        if os.path.isdir(path):
            shutil.copytree(path, portable_res_path, symlinks=True)
            shutil.rmtree(path)
        else:
            shutil.copy2(path, portable_res_path)
            os.remove(path)
            
        manifest["links"].append({
            "src": path,
            "dest": dest_subdir,
            "is_dir": os.path.isdir(portable_res_path)
        })
        
    # 3. Handle registry keys (Wine or Windows Native)
    if registry_keys:
        portable_reg_dir = os.path.join(target_dir, "registry")
        os.makedirs(portable_reg_dir, exist_ok=True)
        
        for idx, key in enumerate(registry_keys):
            reg_filename = f"key_{idx}.reg"
            reg_filepath = os.path.join(portable_reg_dir, reg_filename)
            
            print(f"Exporting registry key '{key}' to {reg_filepath}")
            if export_registry(key, reg_filepath, wine_prefix):
                manifest["registry"].append({
                    "key": key,
                    "file": os.path.join("registry", reg_filename)
                })

    # Save manifest file
    manifest_path = os.path.join(target_dir, "symlinkr.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=4)
        
    # 4. Create the links back to their original locations
    apply_profile(target_dir, strategy)
    
    return manifest

def apply_profile(portable_dir, strategy=None):
    """
    Reads the manifest from portable_dir and recreates all links/registry keys on the host.
    """
    portable_dir = os.path.abspath(portable_dir)
    manifest_path = os.path.join(portable_dir, "symlinkr.json")
    
    if not os.path.exists(manifest_path):
        raise FileNotFoundError(f"Manifest not found in {portable_dir}")
        
    with open(manifest_path, "r") as f:
        manifest = json.load(f)
        
    active_strategy = strategy or manifest.get("strategy", "symlink")
    
    # 1. Restore links
    for link in manifest["links"]:
        src = link["src"]
        dest_rel = link["dest"]
        dest_abs = os.path.join(portable_dir, dest_rel)
        
        print(f"Linking {src} -> {dest_abs} (Strategy: {active_strategy})")
        create_safe_symlink(src, dest_abs, strategy=active_strategy)
        
    # 2. Restore registry keys
    prefix = manifest.get("wine_prefix")
    for reg in manifest.get("registry", []):
        reg_file_abs = os.path.join(portable_dir, reg["file"])
        print(f"Importing registry {reg['key']} from {reg_file_abs}")
        import_registry(reg_file_abs, prefix)
            
    return manifest

def remove_profile(portable_dir):
    """
    Removes the links from the host system as specified in the manifest,
    leaving the portable files completely safe and untouched.
    """
    portable_dir = os.path.abspath(portable_dir)
    manifest_path = os.path.join(portable_dir, "symlinkr.json")
    
    if not os.path.exists(manifest_path):
        raise FileNotFoundError(f"Manifest not found in {portable_dir}")
        
    with open(manifest_path, "r") as f:
        manifest = json.load(f)
        
    unlinked_count = 0
    for link in manifest["links"]:
        src = link["src"]
        if remove_symlink(src):
            unlinked_count += 1
            
    return unlinked_count

def check_profile_health(portable_dir):
    """
    Verifies if the links pointing to the portable directory are healthy,
    broken, or missing entirely.
    """
    portable_dir = os.path.abspath(portable_dir)
    manifest_path = os.path.join(portable_dir, "symlinkr.json")
    
    if not os.path.exists(manifest_path):
        return {"status": "missing_manifest", "links": []}
        
    with open(manifest_path, "r") as f:
        manifest = json.load(f)
        
    links_status = []
    healthy = True
    
    for link in manifest["links"]:
        src = link["src"]
        dest_rel = link["dest"]
        dest_abs = os.path.join(portable_dir, dest_rel)
        
        status = "healthy"
        
        # Check exists (considering symlink target)
        exists = os.path.exists(src)
        is_link = os.path.islink(src) or (sys.platform == "win32" and is_junction(src))
        
        if not exists and not is_link:
            status = "missing"
            healthy = False
        elif not is_link:
            status = "mismatched" # exists but is a real file/dir instead of link
            healthy = False
        else:
            # Check target path resolution
            try:
                if sys.platform == "win32" and is_junction(src):
                    # Resolve junction target using Windows dir call
                    target = get_junction_target(src)
                else:
                    target = os.readlink(src)
                    
                if os.path.abspath(target) != os.path.abspath(dest_abs):
                    status = "mismatched_target"
                    healthy = False
                elif not os.path.exists(dest_abs):
                    status = "broken"
                    healthy = False
            except Exception:
                status = "unknown_link_target"
                healthy = False
                
        links_status.append({
            "src": src,
            "dest": dest_abs,
            "status": status
        })
        
    return {
        "name": manifest["name"],
        "format": manifest["format"],
        "type": manifest["type"],
        "healthy": healthy,
        "links": links_status
    }

def is_junction(path):
    """Check if a path is a Windows Directory Junction."""
    if sys.platform != "win32" or not os.path.isdir(path):
        return False
    # Use fsutil or dir check via subprocess
    cmd = f'dir /a "{os.path.dirname(path)}"'
    try:
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        # Check if the folder name is listed as <JUNCTION>
        return f"<JUNCTION>     {os.path.basename(path)}" in res.stdout
    except Exception:
        return False

def get_junction_target(path):
    """Resolves the target of a Windows Directory Junction."""
    cmd = f'dir /a "{os.path.dirname(path)}"'
    try:
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        # Parse output line matching the junction, e.g.:
        # 16/07/2026  08:12    <JUNCTION>     MyJunction [C:\target\path]
        for line in res.stdout.splitlines():
            if f"<JUNCTION>     {os.path.basename(path)}" in line:
                match = re.search(r'\[(.*?)\]', line)
                if match:
                    return match.group(1)
    except Exception:
        pass
    return ""
