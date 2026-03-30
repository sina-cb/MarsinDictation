#!/usr/bin/env python3
"""
MarsinDictation — Unified dev tool.

Usage:
    python devtool/deploy.py [command] [options]

Commands:
    windows     Build and run the Windows app (auto-detected on Windows)
    mac         Build and run the macOS app (auto-detected on macOS)
    iphone      Build the iOS keyboard extension (future)
    android     Build the Android IME (future)
    kill        Kill any running MarsinDictation processes
    clean       Clean all build artifacts

Modes:
    --build         Build and test only — don't run
    --run           Run only — auto-rebuilds if source is dirty
    --test          Build and run tests only
    (default)       Build, test, and run

Options:
    --release       Build in Release configuration (default: Debug)
    --verbose       Show full build output
    --dry-run       Show what would be done without executing
"""

import argparse
import os
import platform
import signal
import subprocess
import sys
import time
from pathlib import Path

# Force UTF-8 for Windows CI runners
if sys.stdout.encoding and sys.stdout.encoding.lower() != 'utf-8':
    sys.stdout.reconfigure(encoding='utf-8')

# ── Colors ────────────────────────────────────────────────────
class C:
    GREEN  = "\033[92m"
    RED    = "\033[91m"
    YELLOW = "\033[93m"
    CYAN   = "\033[96m"
    DIM    = "\033[2m"
    BOLD   = "\033[1m"
    RESET  = "\033[0m"

ROOT = Path(__file__).resolve().parent.parent
WINDOWS_DIR = ROOT / "windows"
APP_PROJECT = "MarsinDictation.App"
SOURCE_EXTENSIONS = {".cs", ".xaml", ".csproj", ".sln", ".json", ".resx"}

# ── Logging ───────────────────────────────────────────────────
import logging

_log_dir = ROOT / "tmp" / "logs"
_log_dir.mkdir(parents=True, exist_ok=True)

logger = logging.getLogger("deploy")
logger.setLevel(logging.DEBUG)

# File handler — plain text, timestamped
_fh = logging.FileHandler(_log_dir / "deploy.log", mode="w", encoding="utf-8")
_fh.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s", datefmt="%H:%M:%S"))
_fh.setLevel(logging.DEBUG)
logger.addHandler(_fh)

def info(msg):
    print(f"{C.CYAN}▸{C.RESET} {msg}")
    logger.info(msg)
def ok(msg):
    print(f"{C.GREEN}✔{C.RESET} {msg}")
    logger.info(msg)
def warn(msg):
    print(f"{C.YELLOW}⚠{C.RESET} {msg}")
    logger.warning(msg)
def fail(msg):
    print(f"{C.RED}✗{C.RESET} {msg}")
    logger.error(msg)
def header(msg):
    print(f"\n{C.BOLD}{C.CYAN}{'─'*56}\n  {msg}\n{'─'*56}{C.RESET}")
    logger.info(f"══ {msg} ══")
def dim(msg):
    print(f"{C.DIM}{msg}{C.RESET}")
    logger.debug(msg)

# ── Step tracker ──────────────────────────────────────────────
results = []

def run_step(name, cmd, cwd=None, dry_run=False, verbose=False):
    """Run a command, track result, return success bool."""
    info(f"{name}...")
    if dry_run:
        dim(f"  [dry-run] {' '.join(str(c) for c in cmd)}")
        results.append((name, "skip"))
        return True

    try:
        kwargs = dict(cwd=str(cwd) if cwd else None, check=True)
        if not verbose:
            kwargs["capture_output"] = True
            kwargs["text"] = True

        subprocess.run(cmd, **kwargs)
        ok(name)
        results.append((name, "ok"))
        return True
    except subprocess.CalledProcessError as e:
        fail(f"{name} — exit code {e.returncode}")
        if not verbose and e.stdout:
            for line in e.stdout.strip().splitlines()[-8:]:
                print(f"  {line}")
        if not verbose and e.stderr:
            for line in e.stderr.strip().splitlines()[-8:]:
                print(f"  {line}")
        results.append((name, "FAIL"))
        return False

def print_summary(start_time):
    elapsed = time.time() - start_time
    print()
    failed = sum(1 for _, s in results if s == "FAIL")
    for name, status in results:
        icon = {"ok": f"{C.GREEN}✔", "skip": f"{C.DIM}~", "FAIL": f"{C.RED}✗"}.get(status, "?")
        print(f"  {icon}{C.RESET} {name}")
    print()
    if failed:
        fail(f"{failed} step(s) failed")
    else:
        ok("All steps completed")
    dim(f"Elapsed: {elapsed:.1f}s")
    return 1 if failed else 0

# ── Dirty detection ───────────────────────────────────────────
def get_output_dll(config="Debug"):
    return WINDOWS_DIR / APP_PROJECT / "bin" / config / "net8.0-windows" / f"{APP_PROJECT}.dll"

def newest_source_mtime(directory):
    newest = 0.0
    for root, _, files in os.walk(directory):
        if "\\bin\\" in root or "/bin/" in root or "\\obj\\" in root or "/obj/" in root:
            continue
        for f in files:
            if Path(f).suffix in SOURCE_EXTENSIONS:
                mtime = os.path.getmtime(os.path.join(root, f))
                if mtime > newest:
                    newest = mtime
    return newest

def is_binary_dirty(config="Debug"):
    dll = get_output_dll(config)
    if not dll.exists():
        info("No existing build found — build required")
        return True

    dll_mtime = dll.stat().st_mtime
    src_mtime = newest_source_mtime(WINDOWS_DIR)

    if src_mtime > dll_mtime:
        delta = src_mtime - dll_mtime
        info(f"Source is {delta:.0f}s newer than binary — rebuild required")
        return True
    else:
        ok("Binary is up-to-date")
        return False

# ── Process management ────────────────────────────────────────
def kill_existing(dry_run=False):
    """Kill any running MarsinDictation processes."""
    info("Checking for existing processes...")
    try:
        result = subprocess.run(
            ["tasklist", "/FI", f"IMAGENAME eq {APP_PROJECT}.exe", "/FO", "CSV", "/NH"],
            capture_output=True, text=True
        )
        if APP_PROJECT in result.stdout:
            if dry_run:
                dim(f"  [dry-run] Would kill {APP_PROJECT}.exe")
                return
            subprocess.run(["taskkill", "/F", "/IM", f"{APP_PROJECT}.exe"], capture_output=True)
            ok(f"Killed existing {APP_PROJECT}")
            time.sleep(0.5)
        else:
            dim("  No existing processes found")
    except Exception as e:
        warn(f"Could not check/kill processes: {e}")

def kill_process_tree(pid):
    """Kill a process and all its children using taskkill /T."""
    try:
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)],
                       capture_output=True, timeout=5)
    except Exception:
        pass

# ── Build pipeline ────────────────────────────────────────────

def ensure_app_icon(dry_run, verbose):
    """Generate app-icon.ico from icon.png dynamically to ensure crisp 256x256 resolution."""
    png_path = ROOT / "icon.png"
    ico_path = WINDOWS_DIR / APP_PROJECT / "Assets" / "app-icon.ico"
    
    if not png_path.exists():
        return
        
    # If ICO doesn't exist or PNG is newer, rebuild ICO
    if ico_path.exists() and png_path.stat().st_mtime <= ico_path.stat().st_mtime:
        return

    info("Generating multi-res app-icon.ico from icon.png...")
    if dry_run:
        results.append(("Generate icon", "skip"))
        return

    try:
        ico_path.parent.mkdir(parents=True, exist_ok=True)
        ps_script = ROOT / "devtool" / "build_icon.ps1"
        cmd = [
            "powershell", "-ExecutionPolicy", "Bypass", "-File", str(ps_script),
            "-InputPath", str(png_path), "-OutputPath", str(ico_path)
        ]
        
        proc = subprocess.run(cmd, check=True, capture_output=not verbose, text=True)
        ok("Generate icon")
        results.append(("Generate icon", "ok"))
    except subprocess.CalledProcessError as e:
        warn(f"Failed to generate icon. Exit code {e.returncode}")
        if not verbose and e.stderr:
            for line in e.stderr.strip().splitlines():
                warn(line)

TEST_PROJECT = "MarsinDictation.Tests"

def do_restore(verbose, dry_run):
    return run_step("Restore packages", ["dotnet", "restore"],
                    cwd=WINDOWS_DIR, dry_run=dry_run, verbose=verbose)

def do_build(config, verbose, dry_run):
    """Build all projects individually (avoids solution x86 platform mismatch)."""
    ensure_app_icon(dry_run, verbose)
    if not do_restore(verbose, dry_run):
        return False
    # Build App (pulls in Core) — output goes to bin/Debug/ matching dotnet run
    if not run_step(f"Build ({config})",
                    ["dotnet", "build", APP_PROJECT, "-c", config, "--no-restore"],
                    cwd=WINDOWS_DIR, dry_run=dry_run, verbose=verbose):
        return False
    # Build Tests (pulls in Core)
    return run_step(f"Build Tests",
                    ["dotnet", "build", TEST_PROJECT, "-c", config, "--no-restore"],
                    cwd=WINDOWS_DIR, dry_run=dry_run, verbose=verbose)

def do_test(config, verbose, dry_run, filter_expr=None):
    """Build and run tests, showing self-documented evidence."""
    if not do_build(config, verbose, dry_run):
        return False

    info("Run tests...")
    if dry_run:
        dim("  [dry-run] dotnet test --no-build")
        results.append(("Run tests", "skip"))
        return True

    import xml.etree.ElementTree as ET
    import tempfile

    trx_dir = tempfile.mkdtemp(prefix="marsin_test_")
    test_cmd = [
        "dotnet", "test", "--no-build", "-c", config,
        "--logger", f"trx;LogFileName=results.trx",
        "--results-directory", trx_dir,
        "--verbosity", "quiet"
    ]
    if filter_expr:
        test_cmd.extend(["--filter", filter_expr])

    try:
        proc = subprocess.run(test_cmd, cwd=str(WINDOWS_DIR),
                             capture_output=True, text=True)

        # Find TRX file
        trx_file = None
        for root_dir, _, files in os.walk(trx_dir):
            for f in files:
                if f.endswith(".trx"):
                    trx_file = os.path.join(root_dir, f)
                    break

        if trx_file and os.path.exists(trx_file):
            tree = ET.parse(trx_file)
            ns = {"t": "http://microsoft.com/schemas/VisualStudio/TeamTest/2010"}
            root = tree.getroot()

            test_results = root.findall(".//t:UnitTestResult", ns)
            suites = {}
            total_passed = 0
            total_failed = 0

            for tr in test_results:
                name = tr.get("testName", "?")
                outcome = tr.get("outcome", "?")

                # Extract test output (evidence from ITestOutputHelper)
                output_el = tr.find(".//t:Output/t:StdOut", ns)
                evidence = output_el.text.strip() if output_el is not None and output_el.text else ""

                # Group by test class
                parts = name.rsplit(".", 1)
                suite = parts[0] if len(parts) > 1 else "Unknown"
                test_name = parts[1] if len(parts) > 1 else name

                if suite not in suites:
                    suites[suite] = []
                suites[suite].append((test_name, outcome, evidence))

                if outcome == "Passed":
                    total_passed += 1
                else:
                    total_failed += 1

            # Display evidence-based results
            print()
            for suite, tests in sorted(suites.items()):
                short_suite = suite.split(".")[-1]
                passed = sum(1 for _, o, _ in tests if o == "Passed")
                print(f"  {C.BOLD}{short_suite}{C.RESET} ({passed}/{len(tests)})")

                for test_name, outcome, evidence in tests:
                    icon = f"{C.GREEN}✔" if outcome == "Passed" else f"{C.RED}✗"
                    print(f"    {icon}{C.RESET} {test_name}")

                    if evidence and verbose:
                        for line in evidence.splitlines():
                            print(f"      {C.DIM}{line}{C.RESET}")
                    elif evidence:
                        # Show SETUP, INTENT and PASS/FAIL lines for compact view
                        for line in evidence.splitlines():
                            stripped = line.strip()
                            if "SETUP:" in stripped or "INTENT:" in stripped or "PASS:" in stripped or "FAIL:" in stripped:
                                print(f"      {C.DIM}{stripped}{C.RESET}")
                print()

            total = total_passed + total_failed
            if total_failed == 0:
                ok(f"All {total} tests passed")
                results.append(("Run tests", "ok"))
            else:
                fail(f"{total_failed}/{total} tests failed")
                results.append(("Run tests", "FAIL"))
                return False
        else:
            if proc.returncode == 0:
                ok("Run tests")
                results.append(("Run tests", "ok"))
            else:
                fail("Run tests")
                if proc.stdout:
                    for line in proc.stdout.strip().splitlines()[-8:]:
                        print(f"  {line}")
                results.append(("Run tests", "FAIL"))
                return False

        import shutil
        shutil.rmtree(trx_dir, ignore_errors=True)

    except Exception as e:
        fail(f"Run tests — {e}")
        results.append(("Run tests", "FAIL"))
        return False

    return True

def do_run(config, dry_run, hold=False):
    """Run the app, handling Ctrl+C by killing the process tree."""
    print()
    header("Running MarsinDictation")
    print(f"  {C.DIM}Stop via: tray icon \u2192 Quit, or Ctrl+C{C.RESET}")
    print(f"  {C.DIM}Hotkeys: Ctrl+Win (hold to record), Alt+Shift+Z (recovery){C.RESET}")
    if hold:
        print(f"  {C.DIM}Logs: %LOCALAPPDATA%/MarsinDictation/logs/app.log{C.RESET}")
    print()

    if dry_run:
        dim(f"  [dry-run] dotnet run --project {APP_PROJECT}")
        return

    # Log file: %LOCALAPPDATA%/MarsinDictation/logs/app.log (matches C# FileLoggerProvider)
    local_app_data = os.environ.get("LOCALAPPDATA", str(Path.home() / "AppData" / "Local"))
    log_file = Path(local_app_data) / "MarsinDictation" / "logs" / "app.log"
    log_file.parent.mkdir(parents=True, exist_ok=True)
    log_file.write_text("", encoding="utf-8")  # Truncate old log

    run_cmd = ["dotnet", "run", "--project", APP_PROJECT, "-c", config, "--no-build"]
    proc = subprocess.Popen(run_cmd, cwd=str(WINDOWS_DIR),
                           creationflags=subprocess.CREATE_NEW_PROCESS_GROUP)

    if hold:
        # Tail the log file until process exits or Ctrl+C
        _tail_log(proc, log_file)
    else:
        try:
            proc.wait()
        except KeyboardInterrupt:
            print()
            info("Ctrl+C — stopping app...")
            kill_process_tree(proc.pid)
            ok("App stopped")

def _print_log_line(line):
    """Print a single log line with color coding."""
    if not line:
        return
    # Colorize by level
    if "[ERR]" in line or "[CRT]" in line:
        print(f"  {C.RED}{line}{C.RESET}")
    elif "[WRN]" in line:
        print(f"  {C.YELLOW}{line}{C.RESET}")
    elif "[DBG]" in line:
        print(f"  {C.DIM}{line}{C.RESET}")
    else:
        print(f"  {line}")

def _tail_log(proc, log_file):
    """Tail a log file while process is alive. Ctrl+C kills both."""
    # Mirror app logs to repo tmp/logs/app.log
    mirror_file = ROOT / "tmp" / "logs" / "app.log"
    mirror_file.parent.mkdir(parents=True, exist_ok=True)

    try:
        # Wait for the log file to appear
        for _ in range(20):
            if log_file.exists() and log_file.stat().st_size > 0:
                break
            time.sleep(0.25)

        if not log_file.exists():
            warn("Log file not created — app may not be writing logs")
            proc.wait()
            return

        with open(log_file, "r", encoding="utf-8", errors="replace") as f, \
             open(mirror_file, "w", encoding="utf-8") as mirror:
            while proc.poll() is None:
                line = f.readline()
                if line:
                    stripped = line.rstrip()
                    _print_log_line(stripped)
                    mirror.write(line)
                    mirror.flush()
                else:
                    time.sleep(0.1)

            # Drain remaining lines
            for line in f:
                stripped = line.rstrip()
                _print_log_line(stripped)
                mirror.write(line)

        print()
        info("App exited")
    except KeyboardInterrupt:
        print()
        info("Ctrl+C — stopping app...")
        kill_process_tree(proc.pid)
        ok("App stopped")

# ── Windows ───────────────────────────────────────────────────
def deploy_windows(args):
    header("MarsinDictation — Windows")
    start = time.time()

    config = "Release" if args.release else "Debug"
    v = args.verbose
    d = args.dry_run

    kill_existing(dry_run=d)
    run_step("Check .NET SDK", ["dotnet", "--version"], dry_run=d, verbose=v)

    if args.install or args.package:
        # --install or --package: publish + release build
        if not do_build("Release", v, d):
            return print_summary(start)
        code = print_summary(start)
        if code != 0:
            return code
        return do_install(dry_run=d, package_only=args.package)

    elif args.test:
        # --test: build + run tests (optionally filtered)
        do_test(config, v, d, filter_expr=args.filter)
        return print_summary(start)

    elif args.run:
        # --run: only build if dirty, then run
        dirty = is_binary_dirty(config)
        if dirty:
            info("Auto-rebuilding dirty binary...")
            if not do_build(config, v, d):
                return print_summary(start)
            run_step("Run tests", ["dotnet", "test", "--no-build", "-c", config, "--verbosity", "quiet"],
                     cwd=WINDOWS_DIR, dry_run=d, verbose=v)
        code = print_summary(start)
        if code == 0:
            do_run(config, d, hold=args.hold)
        return code

    elif args.build:
        # --build: build + test, don't run
        do_build(config, v, d)
        run_step("Run tests", ["dotnet", "test", "--no-build", "-c", config, "--verbosity", "quiet"],
                 cwd=WINDOWS_DIR, dry_run=d, verbose=v)
        return print_summary(start)

    else:
        # Default: build + test + run
        if not do_build(config, v, d):
            return print_summary(start)
        run_step("Run tests", ["dotnet", "test", "--no-build", "-c", config, "--verbosity", "quiet"],
                 cwd=WINDOWS_DIR, dry_run=d, verbose=v)
        code = print_summary(start)
        if code == 0:
            do_run(config, d, hold=args.hold)
        return code

# ── Install ───────────────────────────────────────────────────
INSTALL_DIR = Path(os.environ.get("PROGRAMFILES", r"C:\Program Files")) / "MarsinDictation"
EXE_NAME = "MarsinDictation.App.exe"

def do_install(dry_run=False, package_only=False):
    """Publish self-contained, copy to Program Files (UAC), create desktop shortcut."""
    header("Installing MarsinDictation")

    # 1. dotnet publish → self-contained single-dir
    publish_dir = WINDOWS_DIR / APP_PROJECT / "bin" / "publish"
    publish_cmd = [
        "dotnet", "publish", APP_PROJECT,
        "-c", "Release",
        "-r", "win-x64",
        "--self-contained", "true",
        "-p:PublishSingleFile=false",
        "-p:IncludeNativeLibrariesForSelfExtract=true",
        "-o", str(publish_dir),
    ]
    info("Publishing self-contained app...")
    if dry_run:
        dim(f"  [dry-run] {' '.join(publish_cmd)}")
    else:
        try:
            subprocess.run(publish_cmd, cwd=str(WINDOWS_DIR), check=True,
                         capture_output=True, text=True)
            ok(f"Published to {publish_dir}")
        except subprocess.CalledProcessError as e:
            fail(f"Publish failed — exit code {e.returncode}")
            if e.stderr:
                for line in e.stderr.strip().splitlines()[-5:]:
                    print(f"  {line}")
            return 1

    # 1.5 Download model binary if not cached
    model_name = "ggml-large-v3-turbo-q5_0.bin"
    model_cache = ROOT / "tmp" / model_name
    if not model_cache.exists():
        info(f"Downloading model {model_name} to cache (~547MB)...")
        if not dry_run:
            model_cache.parent.mkdir(parents=True, exist_ok=True)
            import urllib.request
            urllib.request.urlretrieve(f"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{model_name}", str(model_cache))
            ok("Model downloaded")

    if package_only:
        import shutil
        info("Building Redistributable Windows Installer via Inno Setup...")
        iscc_path = shutil.which("iscc") or shutil.which("iscc.exe")
        
        # Check standard Inno Setup installs if lacking in PATH
        if not iscc_path:
            alt_path = Path("C:/Program Files (x86)/Inno Setup 6/ISCC.exe")
            if alt_path.exists():
                iscc_path = str(alt_path)

        if not iscc_path:
            fail("Inno Setup Compiler (iscc) not found in PATH. Required for --package.")
            return 1
            
        import tempfile
        iss_path = ROOT / "tmp" / "MarsinDictation.iss"
        out_dir = ROOT / "tmp" / "installers"
        out_dir.mkdir(parents=True, exist_ok=True)
        
        iss_text = f"""[Setup]
AppName=MarsinDictation
AppVersion=1.0.0
DefaultDirName={{autopf}}\\MarsinDictation
DefaultGroupName=MarsinDictation
OutputBaseFilename=MarsinDictation_Setup_Windows
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
OutputDir={str(out_dir)}

[Files]
Source: "{str(publish_dir)}\\*"; DestDir: "{{app}}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{str(model_cache)}"; DestDir: "{{app}}"; Flags: ignoreversion

[Icons]
Name: "{{group}}\\MarsinDictation"; Filename: "{{app}}\\{EXE_NAME}"
Name: "{{autodesktop}}\\MarsinDictation"; Filename: "{{app}}\\{EXE_NAME}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"
"""
        iss_path.write_text(iss_text, encoding="utf-8")
        if dry_run:
            dim(f"  [dry-run] iscc {iss_path}")
        else:
            try:
                subprocess.run([iscc_path, str(iss_path)], check=True, capture_output=True, text=True)
                ok(f"Created installer: {out_dir / 'MarsinDictation_Setup_Windows.exe'}")
            except subprocess.CalledProcessError as e:
                fail(f"Inno Setup Compilation failed — exit code {e.returncode}")
                if e.stderr:
                    for line in e.stderr.strip().splitlines()[-5:]:
                        print(f"  {line}")
                if e.stdout:
                    for line in e.stdout.strip().splitlines()[-5:]:
                        print(f"  {line}")
                return 1
        return 0

    # 2. Copy to Program Files (requires admin — UAC prompt)
    info(f"Installing to {INSTALL_DIR} (requires admin)...")
    if dry_run:
        dim(f"  [dry-run] robocopy {publish_dir} {INSTALL_DIR}")
        dim(f"  [dry-run] copy {model_cache} {INSTALL_DIR}")
    else:
        # Write a temp .ps1 script to avoid nested-quote issues with spaces in paths
        import tempfile
        script_path = Path(tempfile.mktemp(suffix=".ps1"))
        script_path.write_text(
            f'Start-Process -FilePath "robocopy.exe"'
            f' -ArgumentList @(\'"{publish_dir}"\', \'"{INSTALL_DIR}"\', "/MIR", "/NJH", "/NJS", "/NDL", "/NC", "/NS")'
            f' -Verb RunAs -Wait\n'
            f'Start-Process -FilePath "cmd.exe"'
            f' -ArgumentList @("/C", "copy", "/Y", \'"{model_cache}"\', \'"{INSTALL_DIR}\\{model_name}"\')'
            f' -Verb RunAs -Wait\n',
            encoding="utf-8"
        )
        try:
            subprocess.run(["powershell", "-ExecutionPolicy", "Bypass", "-File", str(script_path)],
                          check=False)
            if INSTALL_DIR.exists() and (INSTALL_DIR / EXE_NAME).exists():
                ok(f"Installed to {INSTALL_DIR}")
            else:
                fail("Installation may have failed — exe not found")
                return 1
        except Exception as e:
            fail(f"Installation failed: {e}")
            return 1
        finally:
            script_path.unlink(missing_ok=True)

    # 3. Create desktop shortcut
    info("Creating desktop shortcut...")
    if dry_run:
        dim("  [dry-run] Create MarsinDictation.lnk on Desktop")
    else:
        desktop = Path.home() / "Desktop"
        shortcut_path = desktop / "MarsinDictation.lnk"
        target = INSTALL_DIR / EXE_NAME

        ps_shortcut = f'''
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut("{shortcut_path}")
$sc.TargetPath = "{target}"
$sc.WorkingDirectory = "{INSTALL_DIR}"
$sc.Description = "MarsinDictation — AI-powered dictation"
$sc.IconLocation = "{target},0"
$sc.Save()

# Force Windows Explorer to refresh its icon cache immediately
Add-Type -MemberDefinition '[DllImport("shell32.dll")] public static extern void SHChangeNotify(uint wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);' -Name SHC -Namespace Win32
[Win32.SHC]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero)
'''
        try:
            subprocess.run(["powershell", "-Command", ps_shortcut],
                         check=True, capture_output=True, text=True)
            ok(f"Desktop shortcut created: {shortcut_path}")
        except subprocess.CalledProcessError as e:
            warn(f"Could not create shortcut: {e}")

    # 4. Copy .env to %LOCALAPPDATA%/MarsinDictation/ (so installed app finds API keys)
    env_src = ROOT / ".env"
    if env_src.exists():
        local_app_data = os.environ.get("LOCALAPPDATA", str(Path.home() / "AppData" / "Local"))
        env_dst = Path(local_app_data) / "MarsinDictation" / ".env"
        env_dst.parent.mkdir(parents=True, exist_ok=True)
        if dry_run:
            dim(f"  [dry-run] Copy .env → {env_dst}")
        else:
            import shutil
            shutil.copy2(str(env_src), str(env_dst))
            ok(f"Copied .env → {env_dst}")
    else:
        warn("No .env file found — installed app will need API keys configured manually")

    print()
    ok("Installation complete!")
    print(f"  {C.DIM}Location: {INSTALL_DIR}{C.RESET}")
    print(f"  {C.DIM}Desktop shortcut: MarsinDictation.lnk{C.RESET}")
    print(f"  {C.DIM}Launch from Start Menu or desktop icon{C.RESET}")
    return 0

# ── Kill / Clean ──────────────────────────────────────────────
def do_kill_cmd(args):
    header("Kill MarsinDictation Processes")
    kill_existing(dry_run=args.dry_run)

def do_clean(args):
    header("Clean Build Artifacts")
    start = time.time()
    run_step("Clean Windows", ["dotnet", "clean"], cwd=WINDOWS_DIR, dry_run=args.dry_run, verbose=args.verbose)
    return print_summary(start)

# ── Stubs ─────────────────────────────────────────────────────
def deploy_mac(args):
    header("MarsinDictation — macOS")
    start = time.time()
    MAC_DIR = ROOT / "mac"

    v = args.verbose
    d = args.dry_run
    config = "Release"  # Always use Release for macOS (avoids duplicate Spotlight entries)

    # Step 1: Check prerequisites
    run_step("Check Xcode CLI tools", ["xcodebuild", "-version"], dry_run=d, verbose=v)

    # Check for xcodegen
    xcodegen_check = subprocess.run(["which", "xcodegen"], capture_output=True)
    if xcodegen_check.returncode != 0:
        warn("XcodeGen not found — installing via Homebrew...")
        run_step("Install XcodeGen", ["brew", "install", "xcodegen"], dry_run=d, verbose=v)

    # Step 2: Regenerate Xcode project from project.yml
    project_yml = MAC_DIR / "project.yml"
    local_xcconfig = MAC_DIR / "Local.xcconfig"
    if not local_xcconfig.exists() and not d:
        local_xcconfig.write_text("// Auto-generated by deploy.py to satisfy xcodegen\n", encoding="utf-8")
        info("Created dummy Local.xcconfig for xcodegen")

    if project_yml.exists():
        run_step("Regenerate Xcode project",
                 ["xcodegen", "generate", "--spec", str(project_yml), "--project", str(MAC_DIR)],
                 cwd=MAC_DIR, dry_run=d, verbose=v)
    else:
        fail("project.yml not found — cannot regenerate Xcode project")
        return print_summary(start)

    xcodeproj = MAC_DIR / "MarsinDictation.xcodeproj"

    if args.install or args.package:
        # --install or --package: build + create DMG installer (always Release, set above)
        build_cmd = [
            "xcodebuild",
            "-project", str(xcodeproj),
            "-scheme", "MarsinDictation",
            "-configuration", config,
            "CODE_SIGN_IDENTITY=-",
            "CODE_SIGNING_ALLOWED=YES",
            "build"
        ]
        build_ok = run_step(f"Build ({config})", build_cmd, cwd=MAC_DIR, dry_run=d, verbose=v)
        if not build_ok:
            return print_summary(start)

        # Find the built .app
        derived_data = Path.home() / "Library" / "Developer" / "Xcode" / "DerivedData"
        app_dir = None
        for p in derived_data.iterdir():
            if p.name.startswith("MarsinDictation-"):
                candidate = p / "Build" / "Products" / config / "MarsinDictation.app"
                if candidate.exists():
                    app_dir = candidate
                    break

        if not app_dir:
            fail("Could not find built MarsinDictation.app in DerivedData")
            return print_summary(start)

        # Create staging directory for DMG contents
        import shutil
        import tempfile

        dmg_output = ROOT / "tmp" / "MarsinDictation.dmg"
        dmg_output.parent.mkdir(parents=True, exist_ok=True)

        with tempfile.TemporaryDirectory() as staging_dir:
            staging = Path(staging_dir)

            # Copy .app bundle
            dst_app = staging / "MarsinDictation.app"
            if d:
                dim(f"  [dry-run] Copy {app_dir} → {dst_app}")
            else:
                info("Copying app bundle to staging...")
                shutil.copytree(str(app_dir), str(dst_app))
                ok(f"App bundle staged")

            # Bundle .env into app Resources (so installed app finds API keys)
            env_src = ROOT / ".env"
            if env_src.exists() and not d:
                env_dst = dst_app / "Contents" / "Resources" / ".env"
                shutil.copy2(str(env_src), str(env_dst))
                ok("Bundled .env into app Resources")
            elif not env_src.exists():
                warn("No .env file found — installed app will need configuration")

            # Create /Applications symlink
            if not d:
                os.symlink("/Applications", str(staging / "Applications"))
                ok("Created Applications symlink")
            else:
                dim("  [dry-run] Create Applications symlink")

            # Remove old DMG if it exists
            if dmg_output.exists() and not d:
                dmg_output.unlink()

            # Create DMG
            dmg_cmd = [
                "hdiutil", "create",
                str(dmg_output),
                "-volname", "MarsinDictation",
                "-srcfolder", str(staging),
                "-ov",
                "-format", "UDZO"  # compressed DMG
            ]
            run_step("Create DMG", dmg_cmd, dry_run=d, verbose=v)

            # Also install directly to /Applications if not purely packaging
            if not d and not args.package:
                import shutil as sh2
                apps_dest = Path("/Applications/MarsinDictation.app")
                if apps_dest.exists():
                    sh2.rmtree(str(apps_dest))
                sh2.copytree(str(dst_app), str(apps_dest))
                ok("Installed to /Applications/MarsinDictation.app")

                # Reset Accessibility so it re-prompts on first launch
                subprocess.run(
                    ["tccutil", "reset", "Accessibility", "com.marsinhq.MarsinDictation"],
                    capture_output=True
                )
                ok("Reset Accessibility — app will prompt on first launch")

        code = print_summary(start)
        if code == 0 and not d:
            print()
            ok("DMG installer created!")
            print(f"  {C.DIM}Location: {dmg_output}{C.RESET}")
            if not args.package:
                print(f"  {C.DIM}Open it and drag MarsinDictation to Applications{C.RESET}")
                info("Opening DMG...")
                subprocess.Popen(["open", str(dmg_output)])
        return code

    elif args.build or args.test:
        # Build via xcodebuild
        build_cmd = [
            "xcodebuild",
            "-project", str(xcodeproj),
            "-scheme", "MarsinDictation",
            "-configuration", config,
            "CODE_SIGN_IDENTITY=-",
            "CODE_SIGNING_ALLOWED=YES",
            "build"
        ]
        run_step(f"Build ({config})", build_cmd, cwd=MAC_DIR, dry_run=d, verbose=v)
        return print_summary(start)

    elif args.run:
        # Open in Xcode and let the user run from there
        if not d:
            info("Opening project in Xcode...")
            subprocess.Popen(["open", str(xcodeproj)])
            ok("Opened MarsinDictation.xcodeproj in Xcode — press ⌘R to run")
        else:
            dim(f"  [dry-run] open {xcodeproj}")
        return print_summary(start)

    else:
        # Default: regenerate + build + open
        build_cmd = [
            "xcodebuild",
            "-project", str(xcodeproj),
            "-scheme", "MarsinDictation",
            "-configuration", config,
            "CODE_SIGN_IDENTITY=-",
            "CODE_SIGNING_ALLOWED=YES",
            "build"
        ]
        run_step(f"Build ({config})", build_cmd, cwd=MAC_DIR, dry_run=d, verbose=v)
        code = print_summary(start)
        if code == 0 and not d:
            info("Opening project in Xcode...")
            subprocess.Popen(["open", str(xcodeproj)])
            ok("Opened MarsinDictation.xcodeproj — press ⌘R to run")
        return code

def deploy_iphone(args):
    header("MarsinDictation — iPhone/iPad")
    warn("iOS deployment not yet implemented")
    dim("  Will use: Xcode + xcodebuild archive")

def deploy_android(args):
    header("MarsinDictation — Android")
    warn("Android deployment not yet implemented")
    dim("  Will use: Gradle + adb install")

# ── OS detection ──────────────────────────────────────────────
def detect_platform():
    s = platform.system()
    if s == "Windows":
        return "windows"
    elif s == "Darwin":
        return "mac"
    else:
        return s.lower()


# ── Main ──────────────────────────────────────────────────────
PLATFORMS = ["windows", "mac", "iphone", "android"]
COMMANDS = PLATFORMS + ["kill", "clean"]

def main():
    parser = argparse.ArgumentParser(
        description="MarsinDictation dev tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""{C.DIM}Examples:
  python devtool/deploy.py                      Auto-detect OS, build + run
  python devtool/deploy.py --build              Build + test only
  python devtool/deploy.py --run                Run (auto-rebuild if dirty)
  python devtool/deploy.py --test               Build + run all tests
  python devtool/deploy.py --test --filter UserVoice  Run specific test(s)
  python devtool/deploy.py --test --verbose     Show full evidence output
  python devtool/deploy.py windows              Explicit platform
  python devtool/deploy.py kill                 Kill running instances
  python devtool/deploy.py clean                Clean build artifacts{C.RESET}"""
    )
    parser.add_argument("command", nargs="?", default=None, choices=COMMANDS,
                       help="Platform or command (auto-detected if omitted)")

    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--build", action="store_true", help="Build and test only")
    mode.add_argument("--run", action="store_true", help="Run only (auto-rebuilds if dirty)")
    mode.add_argument("--test", action="store_true", help="Build and run all tests")
    mode.add_argument("--install", action="store_true",
                       help="Create installer (Windows: Program Files + shortcut, macOS: DMG)")
    mode.add_argument("--package", action="store_true",
                       help="Generate portable redistributable CI installers (Windows EXE, macOS DMG)")

    parser.add_argument("--hold", action="store_true",
                       help="Keep terminal open and tail app logs (tmp/logs/app.log)")

    parser.add_argument("--filter", type=str, default=None,
                       help="Filter tests by name (dotnet test --filter expression)")
    parser.add_argument("--release", action="store_true", help="Release build (default: Debug)")
    parser.add_argument("--verbose", action="store_true", help="Show full build output")
    parser.add_argument("--dry-run", action="store_true", help="Show steps without executing")

    args = parser.parse_args()


    if args.command is None:
        detected = detect_platform()
        info(f"Auto-detected platform: {C.BOLD}{detected}{C.RESET}")
        args.command = detected

    dispatchers = {
        "windows": deploy_windows,
        "mac": deploy_mac,
        "iphone": deploy_iphone,
        "android": deploy_android,
        "kill": do_kill_cmd,
        "clean": do_clean,
    }

    handler = dispatchers.get(args.command)
    if handler is None:
        fail(f"Platform '{args.command}' is not supported.")
        dim(f"  Detected OS: {platform.system()} ({platform.platform()})")
        dim(f"  Supported: {', '.join(PLATFORMS)}")
        sys.exit(1)

    try:
        code = handler(args) or 0
        sys.exit(code)
    except KeyboardInterrupt:
        print(f"\n{C.YELLOW}Interrupted{C.RESET}")
        sys.exit(130)

if __name__ == "__main__":
    main()
