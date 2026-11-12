"""Build both MMF executables with the macOS Command Line Tools on Apple silicon."""
import argparse
import concurrent.futures
import fnmatch
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP = "Mac Mouse Fix"
HELPER = "Mac Mouse Fix Helper"
RESOURCE_BUILD = ("3.1.0", "24898")
MINIMUM_OS = "12.0"


def run(*args):
    subprocess.run(args, check=True)


def project_files(target):
    project = json.loads(subprocess.check_output(
        ["plutil", "-convert", "json", "-o", "-", "Mouse Fix.xcodeproj/project.pbxproj"]))
    objects = project["objects"]
    paths = {}

    def walk(key, parent):
        item = objects[key]
        path = parent / item.get("path", "")
        paths[key] = path
        for child in item.get("children", []):
            walk(child, path)

    project_root = objects[project["rootObject"]]
    walk(project_root["mainGroup"], Path())
    configs = objects[project_root["buildConfigurationList"]]["buildConfigurations"]
    release = next(objects[key]["buildSettings"] for key in configs if objects[key]["name"] == "Release")
    excludes = release["EXCLUDED_SOURCE_FILE_NAMES"].split()
    target_info = next(o for o in objects.values() if o["isa"] == "PBXNativeTarget" and o["name"] == target)
    sources = next(objects[k] for k in target_info["buildPhases"] if objects[k]["isa"] == "PBXSourcesBuildPhase")
    files = [paths[objects[k]["fileRef"]] for k in sources["files"] if "fileRef" in objects[k]]
    files = [p for p in files if not any(fnmatch.fnmatch(p.name, pattern) for pattern in excludes)]
    includes = sorted({p.parent for p in paths.values() if p.suffix in {".h", ".hpp"} and p.is_file()})
    return files, includes


class Compiler:
    def __init__(self, work):
        self.work = work
        sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
        target = ["-target", f"arm64-apple-macos{MINIMUM_OS}"]
        self.swift = ["xcrun", "swiftc", *target, "-sdk", sdk, "-swift-version", "5",
                      "-whole-module-optimization", "-O", "-I", work]
        self.clang = ["xcrun", "clang", *target, "-isysroot", sdk, "-fobjc-arc", "-fblocks", "-fmodules", "-O2"]
        self.frameworks = ["-FFrameworks", "-F" + sdk + "/System/Library/PrivateFrameworks",
                           "-F" + sdk + "/System/Library/Frameworks/ApplicationServices.framework/Frameworks"]
        self.module_dir = work / "ReactiveCocoaObjC"

    def module(self, name, sources, flags=()):
        obj = self.work / (name + ".o")
        run(*self.swift, "-parse-as-library", "-emit-object", "-emit-module", "-module-name", name,
            "-emit-module-path", self.work / (name + ".swiftmodule"), "-o", obj, *flags, *sorted(sources))
        return obj

    def dependencies(self):
        cocoa = Path("Shared/External/ReactiveCocoa-12.0.0")
        headers = (cocoa / "ReactiveCocoaObjC/include").resolve()
        self.module_dir.mkdir()
        (self.module_dir / "module.modulemap").write_text(
            "module ReactiveCocoaObjC { umbrella " + json.dumps(str(headers)) + " export * }\n")
        reactive = self.module("ReactiveSwift", Path("Shared/External/ReactiveSwift-7.1.1/Sources").rglob("*.swift"))
        reactive_cocoa = self.module("ReactiveCocoa", (cocoa / "ReactiveCocoa").rglob("*.swift"),
                                     ["-I", self.module_dir, "-DSWIFT_PACKAGE"])
        aliases = self.work / "ReactiveAliases.o"
        run(*self.clang, "-I", headers, "-c", cocoa / "ReactiveCocoaObjC/ObjCRuntimeAliases.m", "-o", aliases)
        return [reactive, reactive_cocoa, aliases]

    def executable(self, target, deps):
        helper = target == HELPER
        dest = self.work / target
        dest.mkdir()
        files, includes = project_files(target)
        module = target.replace(" ", "_")
        define = "IS_HELPER" if helper else "IS_MAIN_APP"
        bridge = Path("Helper" if helper else "App") / "SupportFiles" / (target + "-Bridging-Header.h")
        cflags = ["-D" + define + "=1", "-DNDEBUG=1", "-IFrameworks/cmark/branch-cjk/headers"]
        if helper:
            cflags.append("-DNO_FILTER=1")
        cflags.extend("-I" + str(directory) for directory in includes)
        header = dest / (module + "-Swift.h")
        swift_obj = self.module(module, [p for p in files if p.suffix == ".swift"],
            ["-import-objc-header", bridge, "-emit-objc-header-path", header, "-D" + define, "-DNDEBUG",
             *self.frameworks, "-I", self.module_dir, *[arg for flag in cflags for arg in ("-Xcc", flag)]])

        def compile_source(source):
            obj = dest / source.with_suffix(".o")
            obj.parent.mkdir(parents=True, exist_ok=True)
            std = "-std=gnu++14" if source.suffix in {".mm", ".cpp"} else "-std=gnu11"
            run(*self.clang, *self.frameworks, *cflags, "-I", dest, std, "-c", source, "-o", obj)
            return obj

        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
            objects = list(pool.map(compile_source, (p for p in files if p.suffix != ".swift")))
        libs = ["-framework", "SkyLight", "-framework", "TextInput", "-framework", "MultitouchSupport", "-lc++"]
        if not helper:
            libs.extend(["-framework", "Sparkle"])
        binary = dest / target
        run(*self.swift, *self.frameworks, swift_obj, *objects, *deps, "Frameworks/cmark/branch-cjk/libcmark.a",
            *libs, "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks", "-o", binary)
        return binary


def package(work, donor, identity):
    compiler = Compiler(work)
    deps = compiler.dependencies()
    bundle = work / (APP + ".app")
    helper_path = Path("Contents/Library/LoginItems") / (HELPER + ".app")
    for name, relative in [(HELPER, helper_path), (APP, Path("."))]:
        print("Building", name, flush=True)
        binary = compiler.executable(name, deps)
        contents = bundle / relative / "Contents"
        upstream = donor / relative / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        shutil.copy2(binary, contents / "MacOS" / name)
        for folder in ["Resources", "Frameworks"]:
            run("ditto", upstream / folder, contents / folder)
        if name == APP:
            run("ditto", upstream / "Library/LaunchAgents", contents / "Library/LaunchAgents")
        info = plistlib.loads((upstream / "Info.plist").read_bytes())
        info["LSMinimumSystemVersion"] = MINIMUM_OS
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        run("codesign", "--force", "--timestamp=none", "--sign", identity, bundle / relative)
    run("codesign", "--verify", "--deep", "--strict", bundle)
    return bundle


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, default=Path("/Applications/Mac Mouse Fix.app"),
                        help="Official 3.1.0 app or a ditto ZIP containing it")
    parser.add_argument("--identity", required=True, help="Code signing identity fingerprint, or - for an ad-hoc test")
    parser.add_argument("--output", type=Path, default=ROOT / "build" / "MacMouseFix-local.zip")
    args = parser.parse_args()
    donor = args.upstream.resolve()
    output = args.output.resolve()
    os.chdir(ROOT)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent, prefix="build-") as temp:
        work = Path(temp)
        if donor.suffix == ".zip":
            run("ditto", "-x", "-k", donor, work / "upstream")
            donor = work / "upstream" / (APP + ".app")
        run("codesign", "--verify", "--strict", "-R", '=anchor apple generic and identifier "com.nuebling.mac-mouse-fix" and certificate leaf[subject.OU] = "LM5Z78756B"', donor)
        info = plistlib.loads((donor / "Contents/Info.plist").read_bytes())
        if (info["CFBundleShortVersionString"], info["CFBundleVersion"]) != RESOURCE_BUILD:
            parser.error("Resource bundle must be official MMF 3.1.0 (24898)")
        bundle = package(work, donor, args.identity)
        archive = work / "MacMouseFix.zip"
        run("ditto", "-c", "-k", "--keepParent", bundle, archive)
        archive.replace(output)
    print(output)


if __name__ == "__main__":
    main()
