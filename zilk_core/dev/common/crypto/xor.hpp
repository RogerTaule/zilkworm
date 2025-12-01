// Copyright 2025 The Silkworm Authors
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <zilk_core/core/common/base.hpp>
#include <zilk_core/core/common/bytes.hpp>

namespace silkworm::sentry::crypto {

void xor_bytes(Bytes& data1, ByteView data2);

}  // namespace silkworm::sentry::crypto
