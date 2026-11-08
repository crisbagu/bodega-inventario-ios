#!/usr/bin/env python3
"""Genera Bodega.xcodeproj/project.pbxproj a partir del árbol de fuentes.

No hace falta Xcode para generarlo: el proyecto se abre y compila en Xcode 15/16+.
Uso:  python3 Tools/generar_xcodeproj.py
"""
import hashlib
import os
import plistlib
import json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_DIR = os.path.join(ROOT, "Bodega.xcodeproj")
PBXPROJ = os.path.join(PROJECT_DIR, "project.pbxproj")
APP_NAME = "Bodega"
TEST_NAME = "BodegaTests"
BUNDLE_ID = "com.local.bodega"


def uid(key: str) -> str:
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()


def collect(root: str, exts):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.endswith(".xcassets")]
        for f in sorted(filenames):
            if os.path.splitext(f)[1] in exts:
                out.append(os.path.join(dirpath, f))
    return sorted(out)


def rel(path: str) -> str:
    return os.path.relpath(path, ROOT)


def file_type(path: str) -> str:
    ext = os.path.splitext(path)[1]
    return {
        ".swift": "sourcecode.swift",
        ".json": "text.json",
        ".plist": "text.plist.xml",
        ".xcassets": "folder.assetcatalog",
        ".md": "net.daringfireball.markdown",
        ".xcdatamodeld": "wrapper.xcdatamodel",
    }.get(ext, "text")


def main():
    os.makedirs(PROJECT_DIR, exist_ok=True)

    swift_app = collect(os.path.join(ROOT, "Bodega"), {".swift"})
    swift_tests = collect(os.path.join(ROOT, TEST_NAME), {".swift"})
    assets = []
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, "Bodega")):
        if dirpath.endswith(".xcassets"):
            assets.append(dirpath)
            dirnames[:] = []
    assets = sorted(set(assets))

    # ------------------------------------------------------------------ refs
    filerefs = {}      # rel path -> uuid
    buildfiles = {}    # rel path -> uuid (sources)
    for p in swift_app + swift_tests:
        r = rel(p)
        filerefs[r] = uid("ref:" + r)
        buildfiles[r] = uid("build:" + r)
    asset_refs = {}
    for a in assets:
        r = rel(a)
        asset_refs[r] = uid("ref:" + r)
        buildfiles[r] = uid("build:" + r)

    # ---------------------------------------------------------------- groups
    # Estructura: root -> Bodega (App/Core/Vision/Services/UI/Resources), BodegaTests, Products
    #
    # IMPORTANTE: los grupos son "virtuales" (tienen name, no path) y los ficheros
    # usan sourceTree = SOURCE_ROOT con su ruta completa desde la raiz del proyecto.
    # Asi la ruta real nunca se duplica (el fallo clasico "Bodega/Bodega/...").
    def group_tree(entries):
        """entries: lista de (ruta_relativa_al_grupo, ruta_completa_desde_RAIZ)."""
        tree = {}
        for group_rel, full in entries:
            parts = group_rel.split(os.sep)
            node = tree
            for part in parts[:-1]:
                node = node.setdefault(part, {})
            node.setdefault("__files__", []).append(full)
        return tree

    APP_DIR = os.path.join(ROOT, "Bodega")
    TEST_DIR = os.path.join(ROOT, TEST_NAME)

    app_entries = [(os.path.relpath(p, APP_DIR), rel(p)) for p in swift_app]
    app_entries += [(os.path.relpath(a, APP_DIR), rel(a)) for a in assets]
    test_entries = [(os.path.relpath(p, TEST_DIR), rel(p)) for p in swift_tests]

    app_tree = group_tree(app_entries)
    test_tree = group_tree(test_entries)

    group_uuids = {}

    def emit_groups(tree, parent_key, path_prefix):
        """Crea PBXGroup (virtual: name, sin path) y devuelve uuid del grupo racine."""
        children = []
        for name in sorted(k for k in tree if k != "__files__"):
            sub = tree[name]
            child_prefix = os.path.join(path_prefix, name) if path_prefix else name
            uid_child = emit_groups(sub, f"{parent_key}/{name}", child_prefix)
            children.append((uid_child, name))
        files = sorted(tree.get("__files__", []))
        file_children = []
        for f in files:
            if f in asset_refs:
                file_children.append((asset_refs[f], os.path.basename(f)))
            else:
                file_children.append((filerefs[f], os.path.basename(f)))
        g = uid("group:" + parent_key)
        group_uuids[parent_key] = g
        # el grupo tiene como hijos subgrupos y archivos
        kids = []
        for cid, name in children:
            kids.append(f"\t\t\t{cid} /* {name} */,")
        for fid, name in file_children:
            kids.append(f"\t\t\t{fid} /* {name} */,")
        kids_str = "\n".join(kids)
        label = os.path.basename(parent_key) or parent_key
        groups_blocks.append(
            f"\t\t{g} /* {label} */ = {{\n"
            f"\t\t\tisa = PBXGroup;\n"
            f"\t\t\tchildren = (\n{kids_str}\n\t\t\t);\n"
            f"\t\t\tname = {label};\n"
            f"\t\t\tsourceTree = \"<group>\";\n"
            f"\t\t}};\n"
        )
        return g

    groups_blocks = []
    app_root = emit_groups(app_tree, "Bodega", "Bodega")
    test_root = emit_groups(test_tree, TEST_NAME, TEST_NAME)

    # ------------------------------------------------------- file references
    # Las rutas son completas desde la raiz del proyecto (SOURCE_ROOT), asi que
    # el grupo donde cuelgan no altera la ruta real que ve Xcode.
    fileref_blocks = []
    for r, u in sorted(filerefs.items()):
        fileref_blocks.append(
            f"\t\t{u} /* {os.path.basename(r)} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {file_type(r)}; path = {r}; sourceTree = SOURCE_ROOT; }};\n"
        )
    for r, u in sorted(asset_refs.items()):
        fileref_blocks.append(
            f"\t\t{u} /* {os.path.basename(r)} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {file_type(r)}; path = {r}; sourceTree = SOURCE_ROOT; }};\n"
        )

    # ----------------------------------------------------------- build files
    build_blocks = []
    app_sources = [rel(p) for p in swift_app]
    test_sources = [rel(p) for p in swift_tests]
    app_resources = [rel(a) for a in assets]
    for r in app_sources:
        build_blocks.append(
            f"\t\t{buildfiles[r]} /* {os.path.basename(r)} in Sources */ = {{isa = PBXBuildFile; fileRef = {filerefs[r]} /* {os.path.basename(r)} */; }};\n"
        )
    for r in test_sources:
        build_blocks.append(
            f"\t\t{buildfiles[r]} /* {os.path.basename(r)} in Sources */ = {{isa = PBXBuildFile; fileRef = {filerefs[r]} /* {os.path.basename(r)} */; }};\n"
        )
    for r in app_resources:
        build_blocks.append(
            f"\t\t{buildfiles[r]} /* {os.path.basename(r)} in Resources */ = {{isa = PBXBuildFile; fileRef = {asset_refs[r]} /* {os.path.basename(r)} */; }};\n"
        )

    # ------------------------------------------------------------- products
    product_app = uid("product:app")
    product_test = uid("product:test")

    # --------------------------------------------------------- build phases
    app_sources_phase = uid("phase:app:sources")
    app_frameworks_phase = uid("phase:app:frameworks")
    app_resources_phase = uid("phase:app:resources")
    test_sources_phase = uid("phase:test:sources")
    test_frameworks_phase = uid("phase:test:frameworks")
    test_resources_phase = uid("phase:test:resources")

    app_sources_entries = "\n".join(
        f"\t\t\t\t{buildfiles[r]} /* {os.path.basename(r)} in Sources */," for r in app_sources
    )
    app_resources_entries = "\n".join(
        f"\t\t\t\t{buildfiles[r]} /* {os.path.basename(r)} in Resources */," for r in app_resources
    )
    test_sources_entries = "\n".join(
        f"\t\t\t\t{buildfiles[r]} /* {os.path.basename(r)} in Sources */," for r in test_sources
    )

    # --------------------------------------------------------- configurations
    project_debug = uid("cfg:project:debug")
    project_release = uid("cfg:project:release")
    app_debug = uid("cfg:app:debug")
    app_release = uid("cfg:app:release")
    test_debug = uid("cfg:test:debug")
    test_release = uid("cfg:test:release")
    project_cfg_list = uid("cfglist:project")
    app_cfg_list = uid("cfglist:app")
    test_cfg_list = uid("cfglist:test")

    common_project = """				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SWIFT_STRICT_CONCURRENCY = minimal;
"""
    common_target = """				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MARKETING_VERSION = 1.0;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
"""
    app_target_extra = """				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				INFOPLIST_KEY_CFBundleDisplayName = Bodega;
				INFOPLIST_KEY_NSCameraUsageDescription = "La camara se usa para fotografiar los productos que entran y salen de la bodega. Las fotos se guardan solo en este iPhone.";
				INFOPLIST_KEY_NSPhotoLibraryUsageDescription = "La fototeca se usa para elegir una foto de un producto cuando la camara no esta disponible.";
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = com.local.bodega;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
"""
    test_target_extra = """				BUNDLE_LOADER = "$(TEST_HOST)";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Bodega.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Bodega";
				PRODUCT_BUNDLE_IDENTIFIER = com.local.bodega.tests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = NO;
"""

    def cfg(uuid, name, body):
        return f"\t\t{uuid} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{body}\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n"

    project_debug_body = common_project + """				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
"""
    project_release_body = common_project + """				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
"""
    app_debug_body = common_target + app_target_extra
    app_release_body = common_target + app_target_extra
    test_debug_body = common_target + test_target_extra
    test_release_body = common_target + test_target_extra

    configurations = (
        cfg(project_debug, "Debug", project_debug_body)
        + cfg(project_release, "Release", project_release_body)
        + cfg(app_debug, "Debug", app_debug_body)
        + cfg(app_release, "Release", app_release_body)
        + cfg(test_debug, "Debug", test_debug_body)
        + cfg(test_release, "Release", test_release_body)
    )

    def cfg_list(uuid, name, debug, release, comment):
        return (
            f"\t\t{uuid} /* Build configuration list for {comment} */ = {{\n"
            f"\t\t\tisa = XCConfigurationList;\n"
            f"\t\t\tbuildConfigurations = (\n"
            f"\t\t\t\t{debug} /* Debug */,\n"
            f"\t\t\t\t{release} /* Release */,\n"
            f"\t\t\t);\n"
            f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
            f"\t\t\tdefaultConfigurationName = Release;\n"
            f"\t\t}};\n"
        )

    configuration_lists = (
        cfg_list(project_cfg_list, "PBXProject", project_debug, project_release, "PBXProject")
        + cfg_list(app_cfg_list, "PBXNativeTarget", app_debug, app_release, f'PBXNativeTarget "{APP_NAME}"')
        + cfg_list(test_cfg_list, "PBXNativeTarget", test_debug, test_release, f'PBXNativeTarget "{TEST_NAME}"')
    )

    # ------------------------------------------------------------- targets
    project_obj = uid("project")
    app_target = uid("target:app")
    test_target = uid("target:test")
    dependency = uid("dependency")
    container_proxy = uid("proxy")

    targets_block = f"""\t\t{app_target} /* {APP_NAME} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {app_cfg_list} /* Build configuration list for PBXNativeTarget "{APP_NAME}" */;
\t\t\tbuildPhases = (
\t\t\t\t{app_sources_phase} /* Sources */,
\t\t\t\t{app_frameworks_phase} /* Frameworks */,
\t\t\t\t{app_resources_phase} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = {APP_NAME};
\t\t\tproductName = {APP_NAME};
\t\t\tproductReference = {product_app} /* {APP_NAME}.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};

\t\t{test_target} /* {TEST_NAME} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {test_cfg_list} /* Build configuration list for PBXNativeTarget "{TEST_NAME}" */;
\t\t\tbuildPhases = (
\t\t\t\t{test_sources_phase} /* Sources */,
\t\t\t\t{test_frameworks_phase} /* Frameworks */,
\t\t\t\t{test_resources_phase} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{dependency} /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = {TEST_NAME};
\t\t\tproductName = {TEST_NAME};
\t\t\tproductReference = {product_test} /* {TEST_NAME}.xctest */;
\t\t\tproductType = "com.apple.product-type.bundle.unit-test";
\t\t}};
"""

    phases_block = f"""\t\t{app_sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{app_sources_entries}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};

\t\t{app_frameworks_phase} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};

\t\t{app_resources_phase} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{app_resources_entries}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};

\t\t{test_sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{test_sources_entries}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};

\t\t{test_frameworks_phase} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};

\t\t{test_resources_phase} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
"""

    products_block = f"""\t\t{product_app} /* {APP_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{product_test} /* {TEST_NAME}.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {TEST_NAME}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
"""

    project_block = f"""\t\t{project_obj} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{app_target} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t\t{test_target} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t\tTestTargetID = {app_target};
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {project_cfg_list} /* Build configuration list for PBXProject "{APP_NAME}" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = es;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\tes,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {uid("group:__root__")};
\t\t\tproductRefGroup = {uid("group:Products")};
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{app_target} /* {APP_NAME} */,
\t\t\t\t{test_target} /* {TEST_NAME} */,
\t\t\t);
\t\t}};

\t\t{dependency} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {app_target} /* {APP_NAME} */;
\t\t\ttargetProxy = {container_proxy} /* PBXContainerItemProxy */;
\t\t}};

\t\t{container_proxy} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {project_obj} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {app_target};
\t\t\tremoteInfo = {APP_NAME};
\t\t}};
"""

    # grupos raíz y Products
    root_children = [f"\t\t\t{app_root} /* Bodega */,", f"\t\t\t{test_root} /* {TEST_NAME} */,",
                     f"\t\t\t{uid('group:Products')} /* Products */,"]
    groups_blocks.append(
        f"\t\t{uid('group:__root__')} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
        + "\n".join(root_children)
        + "\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n"
    )
    groups_blocks.append(
        f"\t\t{uid('group:Products')} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
        f"\t\t\t{product_app} /* {APP_NAME}.app */,\n\t\t\t{product_test} /* {TEST_NAME}.xctest */,\n"
        f"\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n"
    )

    pbx = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{''.join(build_blocks)}/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
\t\t{container_proxy} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {project_obj} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {app_target};
\t\t\tremoteInfo = {APP_NAME};
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
{''.join(fileref_blocks)}{products_block}/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{app_frameworks_phase} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};

\t\t{test_frameworks_phase} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{''.join(groups_blocks)}/* End PBXGroup section */

/* Begin PBXNativeTarget section */
{targets_block}/* End PBXNativeTarget section */

/* Begin PBXProject section */
{project_block}/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{app_resources_phase} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{app_resources_entries}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};

\t\t{test_resources_phase} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{app_sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{app_sources_entries}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};

\t\t{test_sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{test_sources_entries}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t{dependency} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {app_target} /* {APP_NAME} */;
\t\t\ttargetProxy = {container_proxy} /* PBXContainerItemProxy */;
\t\t}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
{configurations}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{configuration_lists}/* End XCConfigurationList section */
\t}};

\trootObject = {project_obj} /* Project object */;
}}
"""

    with open(PBXPROJ, "w", encoding="utf-8") as f:
        f.write(pbx)

    escribir_esquemas(app_target, test_target)

    print(f"Proyecto generado: {PBXPROJ}")
    print(f"  fuentes app: {len(app_sources)}  |  tests: {len(test_sources)}  |  recursos: {len(app_resources)}")

    # Verificacion: cada fichero referenciado debe existir en disco con esa ruta exacta.
    # Asi se detecta el fallo "Bodega/Bodega/..." sin necesidad de Xcode.
    problemas = []
    for r in list(filerefs) + list(asset_refs):
        if not os.path.exists(os.path.join(ROOT, r)):
            problemas.append(r)
    if problemas:
        print("  ✖️  Rutas que NO existen en disco:")
        for p in sorted(problemas):
            print(f"      - {p}")
        raise SystemExit(1)
    print(f"  rutas verificadas en disco: {len(filerefs) + len(asset_refs)} (todas correctas)")


def escribir_esquemas(app_target, test_target):
    """Escribe los esquemas compartidos (Bodega.xcscheme) para que Xcode y
    xcodebuild (CI) usen siempre la misma configuración."""
    carpeta = os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes")
    os.makedirs(carpeta, exist_ok=True)

    def referencia(uuid, nombre, tipo):
        return (f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uuid}" '
                f'BuildableName="{nombre}" BlueprintName="{nombre.split(".")[0]}" '
                f'ReferencedContainer="container:Bodega.xcodeproj"></BuildableReference>')

    app_ref = referencia(app_target, "Bodega.app", "app")
    test_ref = referencia(test_target, "BodegaTests.xctest", "test")

    esquema = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {app_ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            {test_ref}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    with open(os.path.join(carpeta, "Bodega.xcscheme"), "w", encoding="utf-8") as f:
        f.write(esquema)


if __name__ == "__main__":
    main()
