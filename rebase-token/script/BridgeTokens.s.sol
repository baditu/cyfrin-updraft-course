// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract BridgeTokensScript is Script {
    function run(
        address _routerAddress,
        uint64 _destinationChainSelector,
        address _receiverAddress,
        address _tokenToSendAddress,
        uint256 _amountToSend,
        address _linkTokenAddress
    ) public {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);
        tokenAmounts[0] = Client.EVMTokenAmount({token: _tokenToSendAddress, amount: _amountToSend});
        vm.startBroadcast();
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiverAddress),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: _linkTokenAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
        });
        uint256 ccipFee = IRouterClient(_routerAddress).getFee(_destinationChainSelector, message);
        IERC20(_linkTokenAddress).approve(_routerAddress, ccipFee);
        IERC20(_tokenToSendAddress).approve(_routerAddress, _amountToSend);
        IRouterClient(_routerAddress).ccipSend(_destinationChainSelector, message);
        vm.stopBroadcast();
    }
}
