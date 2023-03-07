pragma solidity>0.8.0;//SPDX-License-Identifier:None

import "UserOperation.sol";

interface IAggregator{
    function validateSignatures(UserOperation[]calldata,bytes calldata)external view;
    function validateUserOpSignature(UserOperation calldata)external view returns(bytes memory);
    function aggregateSignatures(UserOperation[]calldata)external view returns(bytes memory);
}