// Copyright 2026 The Zilkworm Authors
// SPDX-License-Identifier: Apache-2.0

#pragma once
#include <evmc/evmc.hpp>
#include <zilk_core/core/common/bytes.hpp>

namespace silkworm::mpt {
using bytes32 = evmc::bytes32;

// ---------------------------------------------
// Store interface: get RLP by hash; sink new nodes
// ---------------------------------------------
class NodeStore {
  public:
    virtual ~NodeStore() = default;

    // Must return the RLP bytes for `hash` (throw or return empty view if missing)
    virtual std::optional<ByteView> get_rlp(const bytes32& hash) const = 0;
    virtual void put_rlp(const bytes32& /*hash*/, const Bytes& /*rlp*/) {}
};

}  // namespace silkworm::mpt