#!/usr/bin/env python3
"""
Script to automatically update VS Code c_cpp_properties.json with Conan include paths
"""

import json
import os
import re
from pathlib import Path

def get_conan_include_paths(conan_dir):
    """Extract include paths from all .pc files in the conan directory"""
    include_paths = []
    conan_path = Path(conan_dir)
    
    if not conan_path.exists():
        print(f"Conan directory {conan_dir} does not exist")
        return include_paths
    
    # Find all .pc files
    pc_files = list(conan_path.glob("*.pc"))
    
    for pc_file in pc_files:
        try:
            with open(pc_file, 'r') as f:
                content = f.read()
                
            # Extract prefix
            prefix_match = re.search(r'^prefix=(.+)$', content, re.MULTILINE)
            if prefix_match:
                prefix = prefix_match.group(1).strip()
                include_path = f"{prefix}/include"
                
                # Check if the include directory actually exists
                if os.path.exists(include_path):
                    include_paths.append(include_path)
                    print(f"Found include path: {include_path}")
                else:
                    print(f"Skipping non-existent path: {include_path}")
                    
        except Exception as e:
            print(f"Error processing {pc_file}: {e}")
    
    return sorted(set(include_paths))  # Remove duplicates and sort

def update_vscode_config(workspace_root, include_paths):
    """Update VS Code c_cpp_properties.json with the include paths"""
    vscode_dir = Path(workspace_root) / ".vscode"
    config_file = vscode_dir / "c_cpp_properties.json"
    
    # Create .vscode directory if it doesn't exist
    vscode_dir.mkdir(exist_ok=True)
    
    # Read existing config or create new one
    if config_file.exists():
        with open(config_file, 'r') as f:
            config = json.load(f)
    else:
        config = {
            "configurations": [
                {
                    "name": "Linux",
                    "includePath": [],
                    "defines": [],
                    "compilerPath": "/usr/bin/gcc",
                    "cStandard": "c17",
                    "cppStandard": "gnu++20",
                    "intelliSenseMode": "linux-gcc-x64"
                }
            ],
            "version": 4
        }
    
    # Update include paths
    config_include_paths = [
        "${workspaceFolder}/**"
    ] + include_paths
    
    # Add compile_commands.json if it exists
    compile_commands = Path(workspace_root) / "build" / "compile_commands.json"
    if compile_commands.exists():
        config["configurations"][0]["compileCommands"] = "${workspaceFolder}/build/compile_commands.json"
    
    config["configurations"][0]["includePath"] = config_include_paths
    
    # Write updated config
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=4)
    
    print(f"Updated {config_file} with {len(include_paths)} include paths")

def main():
    # Get workspace root (script is in scripts/ subdirectory)
    script_dir = Path(__file__).parent
    workspace_root = script_dir.parent
    
    # Conan directory
    conan_dir = workspace_root / "build" / "conan2"
    
    print(f"Workspace: {workspace_root}")
    print(f"Conan directory: {conan_dir}")
    
    # Get include paths from Conan
    include_paths = get_conan_include_paths(conan_dir)
    
    if not include_paths:
        print("No Conan include paths found!")
        return
    
    # Update VS Code configuration
    update_vscode_config(workspace_root, include_paths)
    
    print("Done!")

if __name__ == "__main__":
    main()