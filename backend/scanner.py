import os
import sys
import glob
import re

# Conditionally import winreg for Windows registry access
try:
    import winreg
except ImportError:
    winreg = None

# Standard Native Linux plugin paths
LINUX_PLUGIN_PATHS = {
    "VST2": [
        os.path.expanduser("~/.vst"),
        "/usr/lib/vst",
        "/usr/local/lib/vst"
    ],
    "VST3": [
        os.path.expanduser("~/.vst3"),
        "/usr/lib/vst3",
        "/usr/local/lib/vst3"
    ],
    "CLAP": [
        os.path.expanduser("~/.clap"),
        "/usr/lib/clap",
        "/usr/local/lib/clap"
    ]
}

# Standard Native Windows plugin paths
WINDOWS_PLUGIN_PATHS = {
    "VST2": [
        "C:\\Program Files\\VSTPlugins",
        "C:\\Program Files\\Steinberg\\VSTPlugins",
        "C:\\Program Files (x86)\\VSTPlugins",
        "C:\\Program Files (x86)\\Steinberg\\VSTPlugins"
    ],
    "VST3": [
        "C:\\Program Files\\Common Files\\VST3",
        "C:\\Program Files (x86)\\Common Files\\VST3"
    ],
    "CLAP": [
        "C:\\Program Files\\Common Files\\CLAP",
        "C:\\Program Files (x86)\\Common Files\\CLAP"
    ],
    "AAX": [
        "C:\\Program Files\\Common Files\\Avid\\Audio\\Plug-Ins",
        "C:\\Program Files (x86)\\Common Files\\Avid\\Audio\\Plug-Ins"
    ]
}

# Standard relative paths within a Wine prefix (for Linux Wine scanner)
WINE_RELATIVE_PATHS = {
    "VST2": [
        "drive_c/Program Files/VSTPlugins",
        "drive_c/Program Files/Steinberg/VSTPlugins",
        "drive_c/Program Files (x86)/VSTPlugins"
    ],
    "WINE_VST3": [
        "drive_c/Program Files/Common Files/VST3",
        "drive_c/Program Files (x86)/Common Files/VST3"
    ],
    "WINE_CLAP": [
        "drive_c/Program Files/Common Files/CLAP",
        "drive_c/Program Files (x86)/Common Files/CLAP"
    ],
    "WINE_AAX": [
        "drive_c/Program Files/Common Files/Avid/Audio/Plug-Ins",
        "drive_c/Program Files (x86)/Common Files/Avid/Audio/Plug-Ins"
    ]
}

# Common Windows folders to look for presets/licenses
WINDOWS_RESOURCE_DIRS = [
    "C:\\ProgramData",
    os.path.expandvars("%USERPROFILE%\\AppData\\Roaming"),
    os.path.expandvars("%USERPROFILE%\\AppData\\Local"),
    os.path.expandvars("%USERPROFILE%\\Documents"),
    "C:\\Users\\Public\\Documents"
]

# Common folders within Wine prefix (Linux)
WINE_RESOURCE_DIRS = [
    "drive_c/ProgramData",
    "drive_c/users/Public/Documents",
    "drive_c/users/{user}/AppData/Roaming",
    "drive_c/users/{user}/AppData/Local",
    "drive_c/users/{user}/Documents"
]

LINUX_RESOURCE_DIRS = [
    os.path.expanduser("~/.config"),
    os.path.expanduser("~/.local/share"),
    os.path.expanduser("~/Documents")
]

def get_wine_prefixes():
    """Detect common Wine prefixes on the system (Linux only)."""
    if sys.platform == "win32":
        return [] # No wine prefixes on Windows native

    prefixes = []
    default_prefix = os.path.expanduser("~/.wine")
    if os.path.exists(default_prefix) and os.path.isdir(default_prefix):
        prefixes.append(default_prefix)
    
    bottles_path = os.path.expanduser("~/.var/app/com.usebottles.bottles/data/bottles/bottles")
    if os.path.exists(bottles_path):
        for bottle in os.listdir(bottles_path):
            bp = os.path.join(bottles_path, bottle)
            if os.path.isdir(bp) and os.path.exists(os.path.join(bp, "drive_c")):
                prefixes.append(bp)

    lutris_path = os.path.expanduser("~/Games")
    if os.path.exists(lutris_path):
        for game in os.listdir(lutris_path):
            gp = os.path.join(lutris_path, game)
            if os.path.isdir(gp) and os.path.exists(os.path.join(gp, "drive_c")):
                prefixes.append(gp)

    unique_prefixes = []
    for p in prefixes:
        abs_p = os.path.abspath(p)
        if abs_p not in unique_prefixes:
            unique_prefixes.append(abs_p)

    return unique_prefixes

def find_wine_users(prefix):
    """Find user directories in a Wine prefix."""
    users_path = os.path.join(prefix, "drive_c", "users")
    if not os.path.exists(users_path):
        return ["crossover", "steamuser", "default"]
    
    users = []
    for entry in os.listdir(users_path):
        full_path = os.path.join(users_path, entry)
        if os.path.isdir(full_path) and entry not in ["Public", "All Users", "Default User"]:
            users.append(entry)
    return users or ["crossover"]

def scan_native_plugins():
    """Scan native plugin directories for current platform."""
    plugins = []
    
    # Determine OS paths
    if sys.platform == "win32":
        paths_dict = WINDOWS_PLUGIN_PATHS
    else:
        paths_dict = LINUX_PLUGIN_PATHS
        
    for fmt, paths in paths_dict.items():
        for path in paths:
            if not os.path.exists(path):
                continue
            
            try:
                for entry in os.listdir(path):
                    full_path = os.path.join(path, entry)
                    is_plugin = False
                    
                    if fmt == "VST3" and (entry.lower().endswith(".vst3") or os.path.isdir(full_path)):
                        is_plugin = True
                    elif fmt == "CLAP" and entry.lower().endswith(".clap"):
                        is_plugin = True
                    elif fmt == "AAX" and (entry.lower().endswith(".aaxplugin") or os.path.isdir(full_path)):
                        is_plugin = True
                    elif fmt == "VST2" and (entry.lower().endswith(".so") or entry.lower().endswith(".dll")):
                        is_plugin = True
                    
                    if is_plugin:
                        plugins.append({
                            "name": os.path.splitext(entry)[0],
                            "format": fmt,
                            "path": full_path,
                            "type": "native",
                            "size": get_dir_size(full_path) if os.path.isdir(full_path) else os.path.getsize(full_path)
                        })
            except Exception:
                pass
    return plugins

def scan_wine_plugins(prefix):
    """Scan a specific Wine prefix for Windows plugins (Linux only)."""
    if sys.platform == "win32":
        return []
        
    plugins = []
    if not os.path.exists(prefix):
        return plugins
        
    users = find_wine_users(prefix)
    
    for fmt, rel_paths in WINE_RELATIVE_PATHS.items():
        for rel_path in rel_paths:
            full_search_path = os.path.join(prefix, rel_path)
            if not os.path.exists(full_search_path):
                continue
                
            try:
                for entry in os.listdir(full_search_path):
                    full_path = os.path.join(full_search_path, entry)
                    is_plugin = False
                    
                    if entry.endswith(".vst3") or entry.endswith(".dll") or entry.endswith(".clap") or entry.endswith(".aaxplugin") or os.path.isdir(full_path):
                        if fmt == "WINE_VST3" and (entry.endswith(".vst3") or os.path.isdir(full_path)):
                            is_plugin = True
                        elif fmt == "WINE_CLAP" and entry.endswith(".clap"):
                            is_plugin = True
                        elif fmt == "WINE_AAX" and (entry.endswith(".aaxplugin") or os.path.isdir(full_path)):
                            is_plugin = True
                        elif fmt == "VST2" and entry.endswith(".dll"):
                            is_plugin = True
                    
                    if is_plugin:
                        plugins.append({
                            "name": os.path.splitext(entry)[0],
                            "format": fmt.replace("WINE_", ""),
                            "path": full_path,
                            "type": "wine",
                            "prefix": prefix,
                            "size": get_dir_size(full_path) if os.path.isdir(full_path) else os.path.getsize(full_path)
                        })
            except Exception:
                pass
    return plugins

def get_dir_size(path):
    """Calculate total size of a directory in bytes."""
    total = 0
    try:
        if os.path.islink(path):
            return 0
        if os.path.isfile(path):
            return os.path.getsize(path)
        for dirpath, dirnames, filenames in os.walk(path):
            for f in filenames:
                fp = os.path.join(dirpath, f)
                if not os.path.islink(fp):
                    total += os.path.getsize(fp)
    except Exception:
        pass
    return total

def find_associated_resources(plugin_name, is_wine=False, prefix=None):
    """Scan common folders to suggest resource directories matching the plugin name."""
    suggestions = []
    name_clean = re.sub(r'[^a-zA-Z0-9]', '', plugin_name).lower()
    
    if sys.platform == "win32":
        # 1. Native Windows resources
        for r_dir in WINDOWS_RESOURCE_DIRS:
            if not os.path.exists(r_dir):
                continue
            try:
                for entry in os.listdir(r_dir):
                    entry_clean = re.sub(r'[^a-zA-Z0-9]', '', entry).lower()
                    if name_clean in entry_clean or entry_clean in name_clean:
                        suggestions.append({
                            "path": os.path.abspath(os.path.join(r_dir, entry)),
                            "description": f"Windows {os.path.basename(r_dir)} folder matching '{entry}'"
                        })
            except Exception:
                pass
                
        # 2. Windows registry suggestions
        if winreg:
            for hive_name, hive in [("HKEY_CURRENT_USER", winreg.HKEY_CURRENT_USER), ("HKEY_LOCAL_MACHINE", winreg.HKEY_LOCAL_MACHINE)]:
                try:
                    with winreg.OpenKey(hive, "Software") as key:
                        idx = 0
                        while True:
                            sub_name = winreg.EnumKey(key, idx)
                            sub_clean = re.sub(r'[^a-zA-Z0-9]', '', sub_name).lower()
                            if name_clean in sub_clean or sub_clean in name_clean:
                                suggestions.append({
                                    "path": f"{hive_name}\\Software\\{sub_name}",
                                    "description": f"Windows Registry key suggestion"
                                })
                            idx += 1
                except OSError:
                    pass # Reached end of registry subkeys
    else:
        # Linux / Wine
        if is_wine and prefix:
            users = find_wine_users(prefix)
            for user in users:
                for r_dir in WINE_RESOURCE_DIRS:
                    formatted_dir = r_dir.format(user=user)
                    full_base_path = os.path.join(prefix, formatted_dir)
                    if not os.path.exists(full_base_path):
                        continue
                    
                    try:
                        for entry in os.listdir(full_base_path):
                            entry_clean = re.sub(r'[^a-zA-Z0-9]', '', entry).lower()
                            if name_clean in entry_clean or entry_clean in name_clean:
                                suggestions.append({
                                    "path": os.path.abspath(os.path.join(full_base_path, entry)),
                                    "description": f"Wine {r_dir.split('/')[-1]} folder matching '{entry}'"
                                })
                    except Exception:
                        pass
        else:
            for r_dir in LINUX_RESOURCE_DIRS:
                if not os.path.exists(r_dir):
                    continue
                try:
                    for entry in os.listdir(r_dir):
                        entry_clean = re.sub(r'[^a-zA-Z0-9]', '', entry).lower()
                        if name_clean in entry_clean or entry_clean in name_clean:
                            suggestions.append({
                                "path": os.path.abspath(os.path.join(r_dir, entry)),
                                "description": f"Linux {r_dir.split('/')[-1]} folder matching '{entry}'"
                            })
                except Exception:
                    pass
                
    return suggestions
