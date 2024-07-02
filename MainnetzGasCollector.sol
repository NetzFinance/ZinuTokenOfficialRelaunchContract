// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

interface FeeReward {
    function setContractCreator(address contractAddress)
        external
        returns (bool);
}

contract FeeReceiver {
    FeeReward public constant feeSetterContract =
        FeeReward(0x000000000000000000000000000000000000f000);
}
