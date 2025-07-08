// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Interactions.s.sol";

contract DeployRaffle is Script {
    function run() external {
        deployContract();
    }

    function deployContract() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        FundSubscription fundSubscriptionContract = new FundSubscription();
        AddConsumer addConsumerContract = new AddConsumer();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();

        if (networkConfig.subscriptionId == 0) {
            // create a new subscription
            CreateSubscription createSubscriptionContract = new CreateSubscription();
            (networkConfig.subscriptionId, networkConfig.vrfCoordinator) =
                createSubscriptionContract.createSubscription(networkConfig.vrfCoordinator, networkConfig.account);

            // fund it
            fundSubscriptionContract.fundSubscription(
                networkConfig.vrfCoordinator,
                networkConfig.subscriptionId,
                networkConfig.linkToken,
                networkConfig.account
            );
        }

        vm.startBroadcast(networkConfig.account);
        Raffle raffle = new Raffle(
            networkConfig.entranceFee,
            networkConfig.interval,
            networkConfig.vrfCoordinator,
            networkConfig.gasLane,
            networkConfig.subscriptionId,
            networkConfig.callbackGasLimit
        );
        vm.stopBroadcast();

        // add a consumer
        addConsumerContract.addConsumer(
            networkConfig.vrfCoordinator, networkConfig.subscriptionId, address(raffle), networkConfig.account
        );

        return (raffle, helperConfig);
    }
}
