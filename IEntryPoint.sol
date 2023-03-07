pragma solidity>0.8.0;//SPDX-License-Identifier:None

import "UserOperation.sol";
import "IStakeManager.sol";
import "IAggregator.sol";

interface IEntryPoint is IStakeManager{
    event UserOperationEvent(bytes32 ,address ,address,uint,bool,uint,uint);
    event AccountDeployed(bytes32,address,address,address);
    event UserOperationRevertReason(bytes32,address,uint,bytes);
    event SignatureAggregatorChanged(address);
    error FailedOp(uint,string);
    error SignatureValidationFailed(address);
    error ValidationResult(ReturnInfo,StakeInfo,StakeInfo,StakeInfo);
    error ValidationResultWithAggregation(ReturnInfo,StakeInfo,StakeInfo,StakeInfo,AggregatorStakeInfo);
    error SenderAddressResult(address);
    error ExecutionResult(uint,uint,uint48,uint48,bool,bytes);
    struct UserOpsPerAggregator{UserOperation[]userOps;IAggregator aggregator;bytes signature;}
    struct ReturnInfo{uint preOpGas;uint prefund;bool sigFailed;uint48 validAfter;uint48 validUntil;bytes paymasterContext;}
    struct AggregatorStakeInfo{address aggregator;StakeInfo stakeInfo;}
    function handleOps(UserOperation[]calldata,address payable)external;
    function handleAggregatedOps(UserOpsPerAggregator[]calldata,address payable)external;
    function getUserOpHash(UserOperation calldata)external view returns(bytes32);
    function simulateValidation(UserOperation calldata)external;
    function getSenderAddress(bytes memory initCode)external;
    function simulateHandleOp(UserOperation calldata, address,bytes calldata)external;
}