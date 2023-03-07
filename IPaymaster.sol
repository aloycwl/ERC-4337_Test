pragma solidity>0.8.0;//SPDX-License-Identifier:None

import"UserOperation.sol";

interface IPaymaster{
    enum PostOpMode{opSucceeded,opReverted,postOpReverted}
    function validatePaymasterUserOp(UserOperation calldata,bytes32,uint)
    external returns(bytes memory,uint);
    function postOp(PostOpMode,bytes calldata,uint)external;
}