#!/usr/bin/env python3
"""
Next Thing Co. C.H.I.P. Yocto 6.0 Setup Assistant
Interactive helper tool to configure bitbake-setup, layers, and build profiles.
"""

import sys
import os
import json
import argparse
import subprocess
from pathlib import Path

BANNER = r"""
============================================================  
 Next Thing Co. C.H.I.P. $9 Computer - BitBake Yocto Assistant
============================================================
"""

CONFIGURATIONS = {
    "1": {
        "id": "chip-poky-nand",
        "name": "Poky Distribution + Onboard NAND Flash (UBI)",
        "description": "Standard Yocto reference distro targeting the onboard NAND flash with UBI/UBIFS.",
        "distro": "poky",
        "storage": "nand",
        "fragments": ["machine/chip", "distro/poky", "storage/chip-nand"],
    },
    "2": {
        "id": "chip-poky-sd-usb",
        "name": "Poky Distribution + MicroSD Breakout / USB Boot",
        "description": "Standard Yocto reference distro configured for external USB drive or microSD breakout.",
        "distro": "poky",
        "storage": "sd-usb",
        "fragments": ["machine/chip", "distro/poky", "storage/chip-sd-usb"],
    },
    "3": {
        "id": "chip-nodistro-nand",
        "name": "Minimal OpenEmbedded (nodistro) + Onboard NAND Flash (UBI)",
        "description": "Ultra-lightweight distroless build with minimal footprint for NAND flash.",
        "distro": "nodistro",
        "storage": "nand",
        "fragments": ["machine/chip", "storage/chip-nand"],
    },
    "4": {
        "id": "chip-nodistro-sd-usb",
        "name": "Minimal OpenEmbedded (nodistro) + MicroSD Breakout / USB Boot",
        "description": "Ultra-lightweight distroless build configured for USB or microSD card.",
        "distro": "nodistro",
        "storage": "sd-usb",
        "fragments": ["machine/chip", "storage/chip-sd-usb"],
    },
}

NAND_VARIANTS = {
    "1": {
        "id": "hynix-mlc",
        "name": "Hynix H27UCG8T2ETR (MLC, 16K Page, 2MB PEB) [Standard C.H.I.P. v1.0]",
        "page_size": "16384",
        "peb_size": "2097152",
        "leb_size": "2064384",
        "max_leb_cnt": "2000",
    },
    "2": {
        "id": "toshiba-slc",
        "name": "Toshiba TC58NVG1S3HTA00 (SLC, 2K/4K Page, 256KB PEB)",
        "page_size": "4096",
        "peb_size": "262144",
        "leb_size": "253952",
        "max_leb_cnt": "1000",
    },
}

BRANCHES = {
    "1": ("wrynose", "Yocto 6.0 Wrynose (Stable / LTS)"),
    "2": ("master",  "Yocto Development (Latest, currently 6.1+)"),
    "3": ("scarthgap", "Yocto 5.0 Scarthgap (Previous LTS)"),
}

# BitBake branch is versioned independently from the OE layer branches
BITBAKE_BRANCH = {
    "wrynose":   "2.18",
    "master":    "master",
    "scarthgap": "2.8",
}


def clear_screen():
    os.system("clear")


def prompt_choice(title, options_dict, default_key="1"):
    print(f"\n{title}")
    print("-" * len(title))
    for key, val in options_dict.items():
        if isinstance(val, tuple):
            name, desc = val
            marker = " (Recommended)" if key == default_key else ""
            print(f"  [{key}] {name}{marker} - {desc}")
        elif isinstance(val, dict):
            name = val.get("name", "")
            desc = val.get("description", "")
            marker = " (Recommended)" if key == default_key else ""
            desc_str = f" - {desc}" if desc else ""
            print(f"  [{key}] {name}{marker}{desc_str}")

    while True:
        choice = input(f"\nEnter choice [{default_key}]: ").strip()
        if not choice:
            return default_key
        if choice in options_dict:
            return choice
        print("Invalid selection. Please choose a valid option.")


def generate_setup_json(repo_root, selected_config, nand_variant, branch):
    """Generate a bitbake-setup JSON template tailored to the user's selection."""
    rev_name = branch[0]

    config_info = CONFIGURATIONS[selected_config]
    nand_info = NAND_VARIANTS[nand_variant]

    # Determine bb-layers based on distro (nodistro needs fewer layers)
    if config_info["distro"] == "poky":
        bb_layers = [
            "openembedded-core/meta",
            "meta-yocto/meta-poky",
            "meta-yocto/meta-yocto-bsp",
            "meta-openembedded/meta-oe",
            "meta-openembedded/meta-python",
            "meta-openembedded/meta-networking",
            "meta-chip",
        ]
    else:
        bb_layers = [
            "openembedded-core/meta",
            "meta-openembedded/meta-oe",
            "meta-chip",
        ]

    def make_source(uri, rev):
        return {
            "git-remote": {
                "remotes": {"origin": {"uri": uri}},
                "branch": rev,
                "rev": rev,
            }
        }

    # BitBake is versioned on its own branch separate from the OE layer branches
    bb_branch = BITBAKE_BRANCH.get(rev_name, "master")

    sources = {
        "bitbake": make_source("https://git.openembedded.org/bitbake", bb_branch),
        "openembedded-core": make_source("https://git.openembedded.org/openembedded-core", rev_name),
        "meta-openembedded": make_source("https://git.openembedded.org/meta-openembedded", rev_name),
        "meta-chip": make_source("https://github.com/Prof256/meta-chip-6.0", "main"),
    }
    if config_info["distro"] == "poky":
        sources["meta-yocto"] = make_source("https://git.yoctoproject.org/meta-yocto", rev_name)

    setup_data = {
        "version": "1.0",
        "description": f"Next Thing Co. C.H.I.P. - {config_info['name']} ({branch[1]})",
        "sources": sources,
        "bitbake-setup": {
            "configurations": [
                {
                    "name": config_info["id"],
                    "description": config_info["description"],
                    "setup-dir-name": config_info["id"],
                    "bb-layers": bb_layers,
                    "oe-fragments": config_info["fragments"],
                }
            ]
        },
    }

    out_path = repo_root / "bitbake-setup" / f"{config_info['id']}.conf.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(setup_data, f, indent=2)

    return out_path


def generate_local_conf_snippet(selected_config, nand_variant, enable_wifi):
    """Generate local.conf snippet for users wishing to set up manually."""
    config_info = CONFIGURATIONS[selected_config]
    nand_info = NAND_VARIANTS[nand_variant]

    snippet = [
        "# ================================================================",
        "# C.H.I.P. Configuration Snippet (for conf/local.conf)",
        "# ================================================================",
        'MACHINE = "chip"',
    ]

    if config_info["distro"] == "poky":
        snippet.append('DISTRO = "poky"')

    if config_info["storage"] == "nand":
        snippet.append('IMAGE_FSTYPES += " ubi"')
        snippet.append(f'CHIP_NAND_TYPE = "{nand_info["id"]}"')
        snippet.append(f'CHIP_UBI_PAGE_SIZE = "{nand_info["page_size"]}"')
        snippet.append(f'CHIP_UBI_PEB_SIZE = "{nand_info["peb_size"]}"')
        snippet.append(f'CHIP_UBI_LEB_SIZE = "{nand_info["leb_size"]}"')
        snippet.append(f'CHIP_UBI_MAX_LEB_CNT = "{nand_info["max_leb_cnt"]}"')
    else:
        snippet.append('IMAGE_FSTYPES += " ext4 wic"')

    if enable_wifi:
        snippet.append('MACHINE_EXTRA_RRECOMMENDS += " kernel-module-r8723bs rtl8723bs linux-firmware-rtl8723"')

    snippet.append("# Parallelism settings (adjust to your host CPU)")
    snippet.append('BB_NUMBER_THREADS ?= "${@oe.utils.cpu_count()}"')
    snippet.append('PARALLEL_MAKE ?= "-j ${@oe.utils.cpu_count()}"')

    return "\n".join(snippet) + "\n"


def main():
    parser = argparse.ArgumentParser(description="Next Thing Co. C.H.I.P. Yocto 6.0 Setup Assistant")
    parser.add_argument("--profile", choices=list(CONFIGURATIONS.keys()), help="Configuration profile (1-4)")
    parser.add_argument("--nand", choices=list(NAND_VARIANTS.keys()), default="1", help="NAND chip variant (1-2)")
    parser.add_argument("--branch", choices=list(BRANCHES.keys()), default="1", help="Yocto branch (1=wrynose/6.0, 2=master/latest, 3=scarthgap/5.0)")
    parser.add_argument("--no-wifi", action="store_true", help="Disable Wi-Fi/Bluetooth drivers")
    parser.add_argument("--init", action="store_true", help="Directly run bitbake-setup init after configuring")
    parser.add_argument("--list", action="store_true", help="List available configuration profiles and exit")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent

    if args.list:
        print("\nAvailable C.H.I.P. Configurations:")
        for k, v in CONFIGURATIONS.items():
            print(f"  [{k}] {v['name']}\n      -> {v['description']}")
        return 0

    print(BANNER)

    if not args.profile:
        print("Welcome! This wizard helps you configure Yocto 6.0 build files for the C.H.I.P.")
        cfg_choice = prompt_choice("Select Build Profile:", CONFIGURATIONS, default_key="1")
        nand_choice = "1"
        if CONFIGURATIONS[cfg_choice]["storage"] == "nand":
            nand_choice = prompt_choice("Select Onboard NAND Flash Type:", NAND_VARIANTS, default_key="1")
        branch_choice = prompt_choice("Select Yocto Release Branch:", BRANCHES, default_key="1")        wifi_in = input("\nEnable Realtek RTL8723BS Wi-Fi & Bluetooth? (Y/n) [Y]: ").strip().lower()
        enable_wifi = wifi_in not in ["n", "no"]
    else:
        cfg_choice = args.profile
        nand_choice = args.nand
        branch_choice = args.branch
        enable_wifi = not args.no_wifi

    # 1. Generate customized setup JSON
    json_path = generate_setup_json(repo_root, cfg_choice, nand_choice, BRANCHES[branch_choice])
    
    # 2. Generate local.conf helper snippet
    snippet = generate_local_conf_snippet(cfg_choice, nand_choice, enable_wifi)
    snippet_path = repo_root / "conf" / "local.conf.sample"
    with open(snippet_path, "w", encoding="utf-8") as f:
        f.write(snippet)

    print("\n" + "=" * 60)
    print(" Configuration successfully generated!")
    print("=" * 60)
    print(f"  * Generated bitbake-setup config: {json_path}")
    print(f"  * Generated local.conf sample:   {snippet_path}")
    print("\nNext Steps:")
    print("------------------------------------------------------------")
    print("Option A: Using modern 'bitbake-setup' (Automated)")
    print("  1. Ensure bitbake-setup is available in your Python environment:")
    print("       pip install bitbake-setup")
    print(f"  2. Initialize your workspace pointing to the generated template:")
    print(f"       bitbake-setup init {json_path}")
    print("  3. Build the minimal image:")
    print("       bitbake chip-image-minimal")
    print("\nOption B: Using traditional OpenEmbedded environment")
    print("  1. Clone poky and meta-openembedded alongside meta-chip")
    print("  2. source poky/oe-init-build-env build")
    print(f"  3. bitbake-layers add-layer ../meta-chip")
    print(f"  4. Append {snippet_path.name} to conf/local.conf")
    print("  5. bitbake chip-image-minimal")
    print("=" * 60)

    if args.init:
        print("\nInvoking bitbake-setup init...")
        try:
            subprocess.run(["bitbake-setup", "init", str(json_path)], check=True)
        except FileNotFoundError:
            print("[Error] 'bitbake-setup' command not found. Install with: pip install bitbake-setup")
            return 1
        except subprocess.CalledProcessError as e:
            print(f"[Error] bitbake-setup init failed: {e}")
            return e.returncode

    return 0


if __name__ == "__main__":
    sys.exit(main())

