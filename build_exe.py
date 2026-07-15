import sys
import os
import subprocess

def install_and_build():
    print("📦 SymLinkr Standalone Executable Builder")
    print("-----------------------------------------")
    
    # 1. Install PyInstaller if not present
    try:
        import PyInstaller
        print("✅ PyInstaller is already installed.")
    except ImportError:
        print("Installing PyInstaller dependency...")
        subprocess.run([sys.executable, "-m", "pip", "install", "pyinstaller"], check=True)
        import PyInstaller
        print("✅ PyInstaller installed successfully.")

    # 2. Configure path separator for PyInstaller --add-data
    # Windows uses ';' to separate source and destination, Linux/macOS uses ':'
    sep = ";" if sys.platform == "win32" else ":"
    
    # Ensure build directories exist
    os.makedirs("dist", exist_ok=True)

    # 3. Build packaging arguments
    pyinstaller_args = [
        "backend/app.py",
        "--name=symlinkr",
        "--onefile",
        f"--add-data=frontend{sep}frontend",
        "--clean",
        "--noconfirm"
    ]
    
    # Run PyInstaller
    print(f"🚀 Compiling SymLinkr using PyInstaller args: {pyinstaller_args}")
    import PyInstaller.__main__
    PyInstaller.__main__.run(pyinstaller_args)
    
    print("\n-----------------------------------------")
    exe_name = "symlinkr.exe" if sys.platform == "win32" else "symlinkr"
    print(f"🎉 Build complete! The executable is located at: dist/{exe_name}")

if __name__ == "__main__":
    install_and_build()
