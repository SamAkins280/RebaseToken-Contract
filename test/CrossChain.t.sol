//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interface/IRebaseToken.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

// This is fork cross-chain test
contract CrossChain is Test {
    address owner = makeAddr("owner");
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;

    Vault vault;
    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbSepoliaPool;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    function setUp() public {
        //  Create and select the initial (source) fork (Sepolia)
        // This uses the "sepolia" alias defined in foundry.toml
        sepoliaFork = vm.createSelectFork("sepolia");

        //  Create the destination fork (Arbitrum Sepolia) but don't select it yet
        // This uses the "arb-sepolia" alias defined in foundry.toml
        arbSepoliaFork = vm.createFork("arb-sepolia");

        //  Deploy the CCIP Local Simulator contract
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();

        //  Make the simulator's address persistent across all active forks
        // This is crucial so both the Sepolia and Arbitrum Sepolia forks
        // can interact with the *same* instance of the simulator.
        vm.makePersistent(address(ccipLocalSimulatorFork));

        /**
         * @notice DeFi AK, JUST in case you're coming back to read this code in the future, this is a step-by-step process on chainLink ccip docs
         */
        //1. Deplpy and configure on sepolia
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetails.rnmProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        sepoliaToken.grantMintAndBurnRole(address(Vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(sepoliaToken), address(sepoliaPool)
        );

        vm.stopPrank();

        vm.startPrank(owner);
        //2. Deplpy and configure on Arbitrum sepolia
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.selectFork(arbSepoliaFork);
        arbSepoliaToken = new RebaseToken();
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetails.rnmProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        arbSepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbSepoliaToken)
        );
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbSepoliaToken), address(arbSepoliaPool)
        );

        configureTokenPool(
            sepoliaFork,
            address(sepoliaPool),
            arbSepoliaNetworkDetails.chainSelector,
            address(arbSepoliaPool),
            address(arbSepoliaToken)
        );
        configureTokenPool(
            arbSepoliaFork,
            address(arbSepoliaPool),
            sepoliaNetworkDetails.chainSelector,
            address(sepoliaPool),
            address(sepoliaToken)
        );
        vm.stopPrank();
    }

    function configureTokenPool(
        uint256 fork,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteTokenAdress
    ) public {
        vm.selectFork(fork);
        vm.prank(owner);
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);
        TokenPool.ChainUpdate[] memory chainToAdd = new TokenPool.ChainUpdate[](1);
        // struct ChainUpdate {
        //     uint64 remoteChainSelector;
        //     bytes remotePoolAddresses; // ABI-encoded array of remote pool addresses
        //     bytes remoteTokenAddress;  // ABI-encoded remote token address
        //     RateLimiter.Config outboundRateLimiterConfig;
        //     RateLimiter.Config inboundRateLimiterConfig;
        // }

        chainToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remoteChainAddresses: remotePoolAddresses,
            remoteTokenAdress: abi.encode(remoteTokenAdress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool(localPool).applyChainUpdates(new uint64[](0), chainToAdd);
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        // Create the message to send tokens cross-chain
        vm.selectFork(localFork);
        vm.startPrank(alice);
        Client.EVMTokenAmount[] memory tokenToSendDetails = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount =
            Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        tokenToSendDetails[0] = tokenAmount;
        // Approve the router to burn tokens on users behalf
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(alice), // we need to encode the address to bytes
            data: "", // We don't need any data for this example
            tokenAmounts: tokenToSendDetails, // this needs to be of type EVMTokenAmount[] as you could send multiple tokens
            extraArgs: "", // We don't need any extra args for this example
            feeToken: localNetworkDetails.linkAddress // The token used to pay for the fee
        });
        // Get and approve the fees
        vm.stopPrank();
        // Give the user the fee amount of LINK
        ccipLocalSimulatorFork.requestLinkFromFaucet(
            alice, IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message)
        );
        vm.startPrank(alice);
        IERC20(localNetworkDetails.linkAddress).approve(
            localNetworkDetails.routerAddress,
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message)
        ); // Approve the fee
        // log the values before bridging
        uint256 balanceBeforeBridge = IERC20(address(localToken)).balanceOf(alice);
        console.log("Local balance before bridge: %d", balanceBeforeBridge);

        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message); // Send the message
        uint256 sourceBalanceAfterBridge = IERC20(address(localToken)).balanceOf(alice);
        console.log("Local balance after bridge: %d", sourceBalanceAfterBridge);
        assertEq(sourceBalanceAfterBridge, balanceBeforeBridge - amountToBridge);
        vm.stopPrank();

        vm.selectFork(remoteFork);
        // Pretend it takes 15 minutes to bridge the tokens
        vm.warp(block.timestamp + 900);
        // get initial balance on Arbitrum
        uint256 initialArbBalance = IERC20(address(remoteToken)).balanceOf(alice);
        console.log("Remote balance before bridge: %d", initialArbBalance);
        vm.selectFork(localFork); // in the latest version of chainlink-local, it assumes you are currently on the local fork before calling switchChainAndRouteMessage
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        console.log("Remote user interest rate: %d", remoteToken.getUserInterestRate(alice));
        uint256 destBalance = IERC20(address(remoteToken)).balanceOf(alice);
        console.log("Remote balance after bridge: %d", destBalance);
        assertEq(destBalance, initialArbBalance + amountToBridge);
    }

    // function testBridgeAllTokens() public {
    //     configureTokenPool(
    //         sepoliaFork, sourcePool, destPool, IRebaseToken(address(destRebaseToken)), arbSepoliaNetworkDetails
    //     );
    //     configureTokenPool(
    //         arbSepoliaFork, destPool, sourcePool, IRebaseToken(address(sourceRebaseToken)), sepoliaNetworkDetails
    //     );
    //     // We are working on the source chain (Sepolia)
    //     vm.selectFork(sepoliaFork);
    //     // Pretend a user is interacting with the protocol
    //     // Give the user some ETH
    //     vm.deal(alice, SEND_VALUE);
    //     vm.startPrank(alice);
    //     // Deposit to the vault and receive tokens
    //     Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
    //     // bridge the tokens
    //     console.log("Bridging %d tokens", SEND_VALUE);
    //     uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(alice);
    //     assertEq(startBalance, SEND_VALUE);
    //     vm.stopPrank();
    //     // bridge ALL TOKENS to the destination chain
    //     bridgeTokens(
    //         SEND_VALUE,
    //         sepoliaFork,
    //         arbSepoliaFork,
    //         sepoliaNetworkDetails,
    //         arbSepoliaNetworkDetails,
    //         sourceRebaseToken,
    //         destRebaseToken
    //     );
    // }

    // function testBridgeAllTokensBack() public {
    //     configureTokenPool(
    //         sepoliaFork, sourcePool, destPool, IRebaseToken(address(destRebaseToken)), arbSepoliaNetworkDetails
    //     );
    //     configureTokenPool(
    //         arbSepoliaFork, destPool, sourcePool, IRebaseToken(address(sourceRebaseToken)), sepoliaNetworkDetails
    //     );
    //     // We are working on the source chain (Sepolia)
    //     vm.selectFork(sepoliaFork);
    //     // Pretend a user is interacting with the protocol
    //     // Give the user some ETH
    //     vm.deal(alice, SEND_VALUE);
    //     vm.startPrank(alice);
    //     // Deposit to the vault and receive tokens
    //     Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
    //     // bridge the tokens
    //     console.log("Bridging %d tokens", SEND_VALUE);
    //     uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(alice);
    //     assertEq(startBalance, SEND_VALUE);
    //     vm.stopPrank();
    //     // bridge ALL TOKENS to the destination chain
    //     bridgeTokens(
    //         SEND_VALUE,
    //         sepoliaFork,
    //         arbSepoliaFork,
    //         sepoliaNetworkDetails,
    //         arbSepoliaNetworkDetails,
    //         sourceRebaseToken,
    //         destRebaseToken
    //     );
    //     // bridge back ALL TOKENS to the source chain after 1 hour
    //     vm.selectFork(arbSepoliaFork);
    //     console.log("User Balance Before Warp: %d", destRebaseToken.balanceOf(alice));
    //     vm.warp(block.timestamp + 3600);
    //     console.log("User Balance After Warp: %d", destRebaseToken.balanceOf(alice));
    //     uint256 destBalance = IERC20(address(destRebaseToken)).balanceOf(alice);
    //     console.log("Amount bridging back %d tokens ", destBalance);
    //     bridgeTokens(
    //         destBalance,
    //         arbSepoliaFork,
    //         sepoliaFork,
    //         arbSepoliaNetworkDetails,
    //         sepoliaNetworkDetails,
    //         destRebaseToken,
    //         sourceRebaseToken
    //     );
    // }

    // function testBridgeTwice() public {
    //     configureTokenPool(
    //         sepoliaFork, sourcePool, destPool, IRebaseToken(address(destRebaseToken)), arbSepoliaNetworkDetails
    //     );
    //     configureTokenPool(
    //         arbSepoliaFork, destPool, sourcePool, IRebaseToken(address(sourceRebaseToken)), sepoliaNetworkDetails
    //     );
    //     // We are working on the source chain (Sepolia)
    //     vm.selectFork(sepoliaFork);
    //     // Pretend a user is interacting with the protocol
    //     // Give the user some ETH
    //     vm.deal(alice, SEND_VALUE);
    //     vm.startPrank(alice);
    //     // Deposit to the vault and receive tokens
    //     Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
    //     uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(alice);
    //     assertEq(startBalance, SEND_VALUE);
    //     vm.stopPrank();
    //     // bridge half tokens to the destination chain
    //     // bridge the tokens
    //     console.log("Bridging %d tokens (first bridging event)", SEND_VALUE / 2);
    //     bridgeTokens(
    //         SEND_VALUE / 2,
    //         sepoliaFork,
    //         arbSepoliaFork,
    //         sepoliaNetworkDetails,
    //         arbSepoliaNetworkDetails,
    //         sourceRebaseToken,
    //         destRebaseToken
    //     );
    //     // wait 1 hour for the interest to accrue
    //     vm.selectFork(sepoliaFork);
    //     vm.warp(block.timestamp + 3600);
    //     uint256 newSourceBalance = IERC20(address(sourceRebaseToken)).balanceOf(alice);
    //     // bridge the tokens
    //     console.log("Bridging %d tokens (second bridging event)", newSourceBalance);
    //     bridgeTokens(
    //         newSourceBalance,
    //         sepoliaFork,
    //         arbSepoliaFork,
    //         sepoliaNetworkDetails,
    //         arbSepoliaNetworkDetails,
    //         sourceRebaseToken,
    //         destRebaseToken
    //     );
    //     // bridge back ALL TOKENS to the source chain after 1 hour
    //     vm.selectFork(arbSepoliaFork);
    //     // wait an hour for the tokens to accrue interest on the destination chain
    //     console.log("User Balance Before Warp: %d", destRebaseToken.balanceOf(alice));
    //     vm.warp(block.timestamp + 3600);
    //     console.log("User Balance After Warp: %d", destRebaseToken.balanceOf(alice));
    //     uint256 destBalance = IERC20(address(destRebaseToken)).balanceOf(alice);
    //     console.log("Amount bridging back %d tokens ", destBalance);
    //     bridgeTokens(
    //         destBalance,
    //         arbSepoliaFork,
    //         sepoliaFork,
    //         arbSepoliaNetworkDetails,
    //         sepoliaNetworkDetails,
    //         destRebaseToken,
    //         sourceRebaseToken
    //     );
    // }
}
