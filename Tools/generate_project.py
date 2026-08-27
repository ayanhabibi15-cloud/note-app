#!/usr/bin/env python3
"""Regenerate Inkwell.xcodeproj/project.pbxproj from the files on disk.

The Xcode project format lists every source file three times (a file
reference, a build file, and a membership in the Sources phase), which makes
hand-editing it after adding a Swift file both tedious and easy to get wrong.
This script walks Inkwell/ and rewrites those sections, so adding a file is
just:

    python3 Tools/generate_project.py

Object identifiers are derived from a hash of the file's path, so re-running
the script produces a byte-identical project and never churns the diff.
Everything outside the file lists — build settings, the target, the scheme —
lives in the TEMPLATE below and is the single place to change them.
"""

from __future__ import annotations

import hashlib
import pathlib
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
PROJECT_DIR = REPO_ROOT / "Inkwell"
SOURCE_ROOT = PROJECT_DIR / "Inkwell"
PBXPROJ = PROJECT_DIR / "Inkwell.xcodeproj" / "project.pbxproj"

# Subdirectories of Inkwell/ that become groups, in the order they should
# appear in the navigator. Files directly inside Inkwell/ come first.
GROUP_ORDER = ["Models", "Views", "Services", "Support"]

RESOURCE_NAMES = ["Assets.xcassets"]


def object_id(*parts: str) -> str:
    """A stable 24-character uppercase hex id, the shape Xcode expects."""
    digest = hashlib.md5("::".join(parts).encode("utf-8")).hexdigest()
    return digest[:24].upper()


def collect() -> tuple[list[str], dict[str, list[str]]]:
    """Returns (root-level swift files, {group name: [swift files]})."""
    if not SOURCE_ROOT.is_dir():
        sys.exit(f"Source directory not found: {SOURCE_ROOT}")

    root_files = sorted(p.name for p in SOURCE_ROOT.glob("*.swift"))

    groups: dict[str, list[str]] = {}
    for name in GROUP_ORDER:
        directory = SOURCE_ROOT / name
        if not directory.is_dir():
            continue
        files = sorted(p.name for p in directory.glob("*.swift"))
        if files:
            groups[name] = files

    # Catch a new subdirectory that nobody added to GROUP_ORDER, rather than
    # silently dropping its files out of the build.
    for directory in sorted(SOURCE_ROOT.iterdir()):
        if not directory.is_dir() or directory.name in groups:
            continue
        if directory.name in RESOURCE_NAMES or directory.suffix == ".xcassets":
            continue
        if any(directory.glob("*.swift")):
            sys.exit(
                f"Directory {directory.name}/ has Swift files but isn't in "
                f"GROUP_ORDER. Add it to Tools/generate_project.py."
            )

    return root_files, groups


def build_sections(root_files: list[str], groups: dict[str, list[str]]) -> dict[str, str]:
    build_file_lines: list[str] = []
    file_ref_lines: list[str] = []
    sources_lines: list[str] = []

    def add_source(relative_path: str, name: str) -> str:
        file_ref = object_id("fileRef", relative_path)
        build_file = object_id("buildFile", relative_path)
        build_file_lines.append(
            f"\t\t{build_file} /* {name} in Sources */ = {{isa = PBXBuildFile; "
            f"fileRef = {file_ref} /* {name} */; }};"
        )
        file_ref_lines.append(
            f"\t\t{file_ref} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};"
        )
        sources_lines.append(f"\t\t\t\t{build_file} /* {name} in Sources */,")
        return file_ref

    root_children: list[str] = []
    for name in root_files:
        ref = add_source(name, name)
        root_children.append(f"\t\t\t\t{ref} /* {name} */,")

    group_blocks: list[str] = []
    for group_name, files in groups.items():
        group_id = object_id("group", group_name)
        children: list[str] = []
        for name in files:
            ref = add_source(f"{group_name}/{name}", name)
            children.append(f"\t\t\t\t{ref} /* {name} */,")
        group_blocks.append(
            f"\t\t{group_id} /* {group_name} */ = {{\n"
            f"\t\t\tisa = PBXGroup;\n"
            f"\t\t\tchildren = (\n" + "\n".join(children) + "\n"
            f"\t\t\t);\n"
            f"\t\t\tpath = {group_name};\n"
            f"\t\t\tsourceTree = \"<group>\";\n"
            f"\t\t}};"
        )
        root_children.append(f"\t\t\t\t{group_id} /* {group_name} */,")

    # Resources
    resource_lines: list[str] = []
    for name in RESOURCE_NAMES:
        if not (SOURCE_ROOT / name).exists():
            continue
        file_ref = object_id("fileRef", name)
        build_file = object_id("buildFile", name)
        build_file_lines.append(
            f"\t\t{build_file} /* {name} in Resources */ = {{isa = PBXBuildFile; "
            f"fileRef = {file_ref} /* {name} */; }};"
        )
        file_ref_lines.append(
            f"\t\t{file_ref} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = folder.assetcatalog; path = {name}; sourceTree = \"<group>\"; }};"
        )
        resource_lines.append(f"\t\t\t\t{build_file} /* {name} in Resources */,")
        root_children.append(f"\t\t\t\t{file_ref} /* {name} */,")

    return {
        "build_files": "\n".join(build_file_lines),
        "file_refs": "\n".join(file_ref_lines),
        "sources": "\n".join(sources_lines),
        "resources": "\n".join(resource_lines),
        "group_blocks": "\n".join(group_blocks),
        "root_children": "\n".join(root_children),
    }


# Fixed identifiers for the objects that don't depend on the file list.
IDS = {
    "product": object_id("product", "Inkwell.app"),
    "frameworks_phase": object_id("phase", "frameworks"),
    "sources_phase": object_id("phase", "sources"),
    "resources_phase": object_id("phase", "resources"),
    "app_group": object_id("group", "Inkwell"),
    "products_group": object_id("group", "Products"),
    "main_group": object_id("group", "main"),
    "target": object_id("target", "Inkwell"),
    "project": object_id("project", "Inkwell"),
    "project_config_list": object_id("configList", "project"),
    "target_config_list": object_id("configList", "target"),
    "project_debug": object_id("config", "project", "Debug"),
    "project_release": object_id("config", "project", "Release"),
    "target_debug": object_id("config", "target", "Debug"),
    "target_release": object_id("config", "target", "Release"),
}

# Warning and language settings shared by both project-level configurations.
SHARED_PROJECT_SETTINGS = """\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;
\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_COMMA = YES;
\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;
\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = iphoneos;"""

# Target settings shared by Debug and Release. The INFOPLIST_KEY_* entries are
# how a project with GENERATE_INFOPLIST_FILE = YES declares Info.plist values:
# the calendar and reminders strings are required before iOS will even show the
# permission prompt, and the two file-sharing keys are what expose the app's
# Documents folder in the Files app and in Finder.
SHARED_TARGET_SETTINGS = """\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_ASSET_PATHS = "";
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Inkwell;
\t\t\t\tINFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace = YES;
\t\t\t\tINFOPLIST_KEY_NSCalendarsFullAccessUsageDescription = "Inkwell reads today's events so your morning briefing knows what your day looks like. It never changes your calendar.";
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tINFOPLIST_KEY_NSPhotoLibraryUsageDescription = "Add photos of handouts and whiteboards to your document library.";
\t\t\t\tINFOPLIST_KEY_NSRemindersFullAccessUsageDescription = "Inkwell reads reminders that are due so they appear alongside your tasks in the morning briefing. It never changes your reminders.";
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tINFOPLIST_KEY_UIFileSharingEnabled = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIRequiresFullScreen = NO;
\t\t\t\tINFOPLIST_KEY_UIStatusBarStyle = UIStatusBarStyleDefault;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 2.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "com.inkwell.notesapp";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSUPPORTS_MACCATALYST = YES;
\t\t\t\tSUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";"""


TEMPLATE = """// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{build_files}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{file_refs}
\t\t{product} /* Inkwell.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Inkwell.app; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{frameworks_phase} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{app_group} /* Inkwell */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{root_children}
\t\t\t);
\t\t\tpath = Inkwell;
\t\t\tsourceTree = "<group>";
\t\t}};
{group_blocks}
\t\t{products_group} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{product} /* Inkwell.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{main_group} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{app_group} /* Inkwell */,
\t\t\t\t{products_group} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{target} /* Inkwell */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {target_config_list} /* Build configuration list for PBXNativeTarget "Inkwell" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_phase} /* Sources */,
\t\t\t\t{frameworks_phase} /* Frameworks */,
\t\t\t\t{resources_phase} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = Inkwell;
\t\t\tproductName = Inkwell;
\t\t\tproductReference = {product} /* Inkwell.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{target} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {project_config_list} /* Build configuration list for PBXProject "Inkwell" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group};
\t\t\tproductRefGroup = {products_group} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{target} /* Inkwell */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{resources_phase} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{resources}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{sources}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{project_debug} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{shared_project_settings}
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{project_release} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{shared_project_settings}
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{target_debug} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{shared_target_settings}
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{target_release} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{shared_target_settings}
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{project_config_list} /* Build configuration list for PBXProject "Inkwell" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{project_debug} /* Debug */,
\t\t\t\t{project_release} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{target_config_list} /* Build configuration list for PBXNativeTarget "Inkwell" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{target_debug} /* Debug */,
\t\t\t\t{target_release} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {project} /* Project object */;
}}
"""


def main() -> None:
    root_files, groups = collect()
    sections = build_sections(root_files, groups)

    contents = TEMPLATE.format(
        shared_project_settings=SHARED_PROJECT_SETTINGS,
        shared_target_settings=SHARED_TARGET_SETTINGS,
        **sections,
        **IDS,
    )

    PBXPROJ.parent.mkdir(parents=True, exist_ok=True)
    PBXPROJ.write_text(contents, encoding="utf-8")

    total = len(root_files) + sum(len(files) for files in groups.values())
    print(f"Wrote {PBXPROJ.relative_to(REPO_ROOT)} with {total} Swift files.")
    for group_name, files in groups.items():
        print(f"  {group_name}/: {len(files)}")


if __name__ == "__main__":
    main()
