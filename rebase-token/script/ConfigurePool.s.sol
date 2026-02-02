// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {TokenPool} from "@chainlink/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@chainlink/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

contract ConfigurePoolScript is Script {
    function run(
        address _localPool,
        uint64 _remoteChainSelector,
        address _remotePool,
        address _remoteToken,
        bool _outboundRateLimiterIsEnabled,
        uint128 _outboundRateLimitCapacity,
        uint128 _outboundRateLimitRate,
        bool _inboundRateLimiterIsEnabled,
        uint128 _inboundRateLimitCapacity,
        uint128 _inboundRateLimitRate
    ) public {
        vm.startBroadcast();
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: _remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(_remotePool),
            remoteTokenAddress: abi.encode(_remoteToken),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: _outboundRateLimiterIsEnabled,
                capacity: _outboundRateLimitCapacity,
                rate: _outboundRateLimitRate
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: _inboundRateLimiterIsEnabled,
                capacity: _inboundRateLimitCapacity,
                rate: _inboundRateLimitRate
            })
        });
        TokenPool(_localPool).applyChainUpdates(chainsToAdd);
        vm.stopBroadcast();
    }
}
