pragma solidity>0.8.0;//SPDX-License-Identifier:None

import"UserOperation.sol";

interface IAccount{
    function validateUserOp(UserOperation calldata,bytes32,uint)
    external returns(uint);
}