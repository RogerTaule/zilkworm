# Copyright 2025 The Zilkworm Authors
# Copyright 2025 The Silkworm Authors
# SPDX-License-Identifier: Apache-2.0

from conan import ConanFile


class SilkwormRecipe(ConanFile):
    settings = 'os', 'compiler', 'build_type', 'arch'
    generators = 'CMakeDeps', 'PkgConfigDeps'

    def requirements(self):
        self.requires('magic_enum/0.8.2')
        self.requires('ms-gsl/4.0.0')
        self.requires('nlohmann_json/3.11.3')
