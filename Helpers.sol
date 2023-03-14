pragma solidity>0.8.0;//SPDX-License-Identifier:None

import"Interfaces.sol";

library Exec{
    function call(address to,uint value,bytes memory data,uint txGas)internal returns(bool success){
        assembly{
            success:=call(txGas,to,value,add(data,0x20),mload(data),0,0)
        }
    }
    function staticcall(address to,bytes memory data,uint txGas)internal view returns(bool success){
        assembly{
            success:=staticcall(txGas,to,add(data,0x20),mload(data),0,0)
        }
    }
    function delegateCall(address to,bytes memory data,uint txGas)internal returns(bool success){
        assembly{
            success:=delegatecall(txGas,to,add(data,0x20),mload(data),0,0)
        }
    }
    function getReturnData(uint maxLen) internal pure returns(bytes memory returnData){
        assembly{
            let len:=returndatasize()
            if gt(len,maxLen){
                len:=maxLen
            }
            let ptr:=mload(0x40)
            mstore(0x40,add(ptr,add(len,0x20)))
            mstore(ptr,len)
            returndatacopy(add(ptr,0x20),0,len)
            returnData:=ptr
        }
    }
    function revertWithData(bytes memory returnData)internal pure{
        assembly{
            revert(add(returnData,32),mload(returnData))
        }
    }
    function callAndRevert(address to,bytes memory data,uint maxLen)internal{
        if(!call(to,0,data,gasleft()))revertWithData(getReturnData(maxLen));
    }
}
struct ValidationData{
    address aggregator;
    uint48 validAfter;
    uint48 validUntil;
}
function _parseValidationData(uint validationData)pure returns(ValidationData memory data){
    uint48 validUntil=uint48(validationData>>160);
    if (validUntil==0)validUntil=type(uint48).max;
    return ValidationData(address(uint160(validationData)),uint48(validationData>>208),validUntil);
}
function _intersectTimeRange(uint256 validationData, uint256 paymasterValidationData) pure returns (ValidationData memory){
    (ValidationData memory accountValidationData,ValidationData memory pmValidationData)=
    (_parseValidationData(validationData),_parseValidationData(paymasterValidationData));
    address aggregator=accountValidationData.aggregator;
    if(aggregator==address(0))aggregator=pmValidationData.aggregator;
    (uint48 validAfter,uint48 validUntil,uint48 pmValidAfter,uint48 pmValidUntil)=
    (accountValidationData.validAfter,accountValidationData.validUntil,pmValidationData.validAfter,pmValidationData.validUntil);
    if(validAfter < pmValidAfter)validAfter=pmValidAfter;
    if(validUntil > pmValidUntil)validUntil=pmValidUntil;
    return ValidationData(aggregator,validAfter,validUntil);
}
function _packValidationData(ValidationData memory data)pure returns(uint256){
    return uint160(data.aggregator)|(uint256(data.validUntil)<<160)|(uint256(data.validAfter)<<208);
}
function _packValidationData(bool sigFailed,uint48 validUntil,uint48 validAfter)pure returns(uint256){
    return(sigFailed?1:0)|(uint256(validUntil)<<160)|(uint256(validAfter)<<208);
}

contract SenderCreator {
    function createSender(bytes calldata initCode)external returns(address sender){
        (address factory,bytes memory initCallData)=(address(bytes20(initCode[0:20])),initCode[20:]);
        bool success;
        assembly{
            success:=call(gas(),factory,0,add(initCallData,0x20),mload(initCallData),0,32)
            sender:=mload(0)
        }
        if(!success)sender=address(0); 
    }
}

abstract contract StakeManager is IStakeManager{
    mapping(address=>DepositInfo)public deposits;
    function getDepositInfo(address account)public view returns(DepositInfo memory){
        return deposits[account];
    }
    function _getStakeInfo(address addr)internal view returns(StakeInfo memory info) {
        DepositInfo storage depositInfo=deposits[addr];
        (info.stake,info.unstakeDelaySec)=(depositInfo.stake,depositInfo.unstakeDelaySec);
    }
    function balanceOf(address account)public view returns(uint){
        return deposits[account].deposit;
    }
    receive() external payable{
        depositTo(msg.sender);
    }
    function _incrementDeposit(address account,uint amount)internal{
        deposits[account].deposit+=amount;
    }
    function depositTo(address account)public payable{
        _incrementDeposit(account,msg.value);
    }
    function addStake(uint32 unstakeDelaySec)public payable{
        deposits[msg.sender]=DepositInfo(deposits[msg.sender].deposit,true,deposits[msg.sender].stake+msg.value,unstakeDelaySec,0);
    }
    function unlockStake()external{
        DepositInfo storage info=deposits[msg.sender];
        (info.withdrawTime,info.staked)=(uint48(block.timestamp)+info.unstakeDelaySec,false);
    }
    function withdrawStake(address payable withdrawAddress)external{
        DepositInfo storage info=deposits[msg.sender];
        (info.unstakeDelaySec,info.withdrawTime,info.stake)=(0,0,0);
        (bool success,)=withdrawAddress.call{value:info.stake}("");
        require(success);
    }
    function withdrawTo(address payable withdrawAddress,uint withdrawAmount)external{
        DepositInfo storage info=deposits[msg.sender];
        info.deposit=info.deposit-withdrawAmount;
        (bool success,)=withdrawAddress.call{value:withdrawAmount}("");
        require(success);
    }
}