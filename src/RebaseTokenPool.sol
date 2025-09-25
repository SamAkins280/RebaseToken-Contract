//SPDX-Licenese-Identifier: MIT

pragma solidity ^0.8.24;

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRebaseToken} from "./interface/IRebaseToken.sol"; // Adjust path if your interface is elsewhere
import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol"; // For CCIP structs


contract RebaseTokenPool is TokenPool {
    constructor(IERC20 _token, address[] memory _allowlist, address _rnmProxy, address router) 
    TokenPool(_token, 18, _allowlist, _rnmProxy, router)  {}

    /**
     *@notice function will be called when we are sending tokens from the chain this pool is deployed to, to another chain
    */
    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn) external returns (Pool.LockOrBurnOutV1 memory) {
        _validateLockOrBurn(lockOrBurnIn);

        // address originalSender = abi.decode(lockOrBurnIn.originalSender, (address));
        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);

        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        return Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    /**
     *@notice function will be call when the contract token is receiving tokens 
    */
    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata request) external returns (Pool.ReleaseOrMintOutV1 memory) {
        _validateReleaseOrMint(request);

        uint256 userInterestRate = abi.decode(request.sourcePoolData, (uint256));

        address receiver = request.receiver;

        IRebaseToken(address(i_token)).mint(receiver, request.amount, userInterestRate);

        return Pool.ReleaseOrMintOutV1({
            destinationAmount: request.amount
        });
    }

}    