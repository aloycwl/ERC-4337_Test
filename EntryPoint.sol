pragma solidity>0.8.0;//SPDX-License-Identifier:None

struct UserOperation{
    address sender;uint nonce;bytes initCode;bytes callData;uint callGasLimit;uint verificationGasLimit;
    uint preVerificationGas;uint maxFeePerGas;uint maxPriorityFeePerGas;bytes paymasterAndData;bytes signature;
}
library UserOperationLib {
    function getSender(UserOperation calldata userOp)internal pure returns(address){
        address data;
        assembly {data:=calldataload(userOp)}
        return address(uint160(data));
    }
    function gasPrice(UserOperation calldata userOp)internal view returns(uint){unchecked{
        (uint maxFeePerGas,uint maxPriorityFeePerGas)=(userOp.maxFeePerGas,userOp.maxPriorityFeePerGas);
        return maxFeePerGas==maxPriorityFeePerGas?maxFeePerGas:min(maxFeePerGas,maxPriorityFeePerGas+block.basefee);
    }}
    function pack(UserOperation calldata userOp)internal pure returns(bytes memory ret){
        bytes calldata sig=userOp.signature;
        assembly{
            let ofs:=userOp
            let len:=sub(sub(sig.offset,ofs),32)
            ret:=mload(0x40)
            mstore(0x40,add(ret,add(len,32)))
            mstore(ret,len)
            calldatacopy(add(ret,32),ofs,len)
        }
    }
    function hash(UserOperation calldata userOp)internal pure returns(bytes32){
        return keccak256(pack(userOp));
    }
    function min(uint a,uint b)internal pure returns(uint){
        return a<b?a:b;
    }
}
interface IPaymaster{
    enum PostOpMode{opSucceeded,opReverted,postOpReverted}
    function validatePaymasterUserOp(UserOperation calldata,bytes32,uint)
    external returns(bytes memory,uint);
    function postOp(PostOpMode,bytes calldata,uint)external;
}
interface IAccount{
    function validateUserOp(UserOperation calldata,bytes32,uint)
    external returns(uint);
}
interface IStakeManager {
    event Deposited(address,uint);
    event Withdrawn(address,address,uint);
    event StakeLocked(address,uint,uint);
    event StakeUnlocked(address,uint);
    event StakeWithdrawn(address,address,uint);
    struct DepositInfo{uint deposit;bool staked;uint stake;uint32 unstakeDelaySec;uint48 withdrawTime;}
    struct StakeInfo {uint stake;uint unstakeDelaySec;}
    function getDepositInfo(address)external view returns(DepositInfo memory);
    function balanceOf(address)external view returns(uint);
    function depositTo(address)external payable;
    function addStake(uint32)external payable;
    function unlockStake()external;
    function withdrawStake(address payable)external;
    function withdrawTo(address payable,uint)external;
}
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
interface IAggregator{
    function validateSignatures(UserOperation[]calldata,bytes calldata)external view;
    function validateUserOpSignature(UserOperation calldata)external view returns(bytes memory);
    function aggregateSignatures(UserOperation[]calldata)external view returns(bytes memory);
}

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
    function getReturnData(uint maxLen)internal pure returns(bytes memory returnData){
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
function _intersectTimeRange(uint256 validationData, uint256 paymasterValidationData)pure returns(ValidationData memory){
    (ValidationData memory accountValidationData,ValidationData memory pmValidationData)=
    (_parseValidationData(validationData),_parseValidationData(paymasterValidationData));
    address aggregator=accountValidationData.aggregator;
    if(aggregator==address(0))aggregator=pmValidationData.aggregator;
    (uint48 validAfter,uint48 validUntil,uint48 pmValidAfter,uint48 pmValidUntil)=
    (accountValidationData.validAfter,accountValidationData.validUntil,pmValidationData.validAfter,pmValidationData.validUntil);
    if(validAfter<pmValidAfter)validAfter=pmValidAfter;
    if(validUntil>pmValidUntil)validUntil=pmValidUntil;
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
    function _getStakeInfo(address addr)internal view returns(StakeInfo memory info){
        (info.stake,info.unstakeDelaySec)=(deposits[addr].stake,deposits[addr].unstakeDelaySec);
    }
    function balanceOf(address account)public view returns(uint){
        return deposits[account].deposit;
    }
    receive()external payable{
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
        (info.unstakeDelaySec,deposits[msg.sender].withdrawTime,info.stake)=(0,0,0);
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

contract EntryPoint is IEntryPoint,StakeManager{
    using UserOperationLib for UserOperation;
    SenderCreator private immutable senderCreator=new SenderCreator();
    address private constant SIMULATE_FIND_AGGREGATOR=address(1);
    bytes32 private constant INNER_OUT_OF_GAS=hex'';
    uint private constant REVERT_REASON_MAX_LEN=2048;
    uint public constant SIG_VALIDATION_FAILED=1;
    struct MemoryUserOp{address sender;uint nonce;uint callGasLimit;
        uint verificationGasLimit;uint preVerificationGas;address paymaster;uint maxFeePerGas;uint maxPriorityFeePerGas;}
    struct UserOpInfo{MemoryUserOp mUserOp;bytes32 userOpHash;uint prefund;uint contextOffset;uint preOpGas;}
    
    function _compensate(address payable beneficiary,uint amount)internal{
        (bool success,)=beneficiary.call{value:amount}("");
        require(success);
    }
    function _executeUserOp(uint opIndex,UserOperation calldata userOp,UserOpInfo memory opInfo)private returns(uint collected){
        (uint preGas,bytes memory context)=(gasleft(),getMemoryBytesFromOffset(opInfo.contextOffset));
        try this.innerHandleOp(userOp.callData,opInfo,context)returns(uint _actualGasCost){
            collected=_actualGasCost;
        }catch{
            bytes32 innerRevertCode;
            assembly{
                returndatacopy(0,0,32)
                innerRevertCode:=mload(0)
            }
            if(innerRevertCode==INNER_OUT_OF_GAS)revert FailedOp(opIndex,"");
            collected=_handlePostOp(opIndex,IPaymaster.PostOpMode.postOpReverted,opInfo,context,preGas-gasleft()+opInfo.preOpGas);
        }
    }
    function handleOps(UserOperation[]calldata ops,address payable beneficiary)public{unchecked{
        uint opslen=ops.length;
        UserOpInfo[]memory opInfos=new UserOpInfo[](opslen);
        for(uint i=0;i<opslen;i++){
            (uint validationData,uint pmValidationData)=_validatePrepayment(i,ops[i],opInfos[i]);
            _validateAccountAndPaymasterValidationData(i,validationData,pmValidationData,address(0));
        }
        uint collected=0;
        for(uint i=0;i<opslen;i++)collected+=_executeUserOp(i,ops[i],opInfos[i]);
        _compensate(beneficiary,collected);
    }}
    function handleAggregatedOps(UserOpsPerAggregator[]calldata opsPerAggregator,address payable beneficiary)public{
        (uint opasLen,uint totalOps)=(opsPerAggregator.length,0);
        for(uint i=0;i<opasLen;i++){
            UserOpsPerAggregator calldata opa=opsPerAggregator[i];
            UserOperation[]calldata ops=opa.userOps;
            IAggregator aggregator=opa.aggregator;
            require(address(aggregator)!=address(1));
            if(address(aggregator)!=address(0))
                try aggregator.validateSignatures(ops,opa.signature){}
                catch{
                    revert SignatureValidationFailed(address(aggregator));
                }
            totalOps+=ops.length;
        }
        UserOpInfo[]memory opInfos=new UserOpInfo[](totalOps);
        uint opIndex=0;
        for(uint a=0;a<opasLen;a++){
            UserOpsPerAggregator calldata opa=opsPerAggregator[a];
            UserOperation[]calldata ops=opa.userOps;
            IAggregator aggregator=opa.aggregator;
            for(uint i=0;i<ops.length;i++){
                UserOpInfo memory opInfo=opInfos[opIndex];
                (uint validationData,uint paymasterValidationData)=_validatePrepayment(opIndex,ops[i],opInfo);
                _validateAccountAndPaymasterValidationData(i,validationData,paymasterValidationData,address(aggregator));
                opIndex++;
            }
        }
        uint collected=0;
        opIndex=0;
        for(uint a=0;a<opasLen;a++){
            UserOperation[]calldata ops=opsPerAggregator[a].userOps;
            for(uint i=0;i<ops.length;i++)(collected+=_executeUserOp(opIndex,ops[i],opInfos[opIndex]),opIndex++);
        }
        _compensate(beneficiary,collected);
    }
    function simulateHandleOp(UserOperation calldata op,address target,bytes calldata targetCallData)external override{
        UserOpInfo memory opInfo;
        _simulationOnlyValidations(op);
        (uint validationData,uint paymasterValidationData)=_validatePrepayment(0,op,opInfo);
        ValidationData memory data=_intersectTimeRange(validationData,paymasterValidationData);
        numberMarker();
        numberMarker();
        bool targetSuccess;
        bytes memory targetResult;
        if(target!=address(0))(targetSuccess,targetResult)=target.call(targetCallData);
        revert ExecutionResult(opInfo.preOpGas,_executeUserOp(0,op,opInfo),data.validAfter,
            data.validUntil,targetSuccess,targetResult);
    }
    function innerHandleOp(bytes memory callData,UserOpInfo memory opInfo,bytes calldata context)external
    returns(uint actualGasCost){unchecked{
        uint preGas=gasleft();
        MemoryUserOp memory mUserOp=opInfo.mUserOp;
        uint callGasLimit=mUserOp.callGasLimit;
        if(gasleft()<callGasLimit+mUserOp.verificationGasLimit+5000){
            assembly{
                mstore(0,INNER_OUT_OF_GAS)
                revert(0,32)
            }
        }
        IPaymaster.PostOpMode mode=IPaymaster.PostOpMode.opSucceeded;
        if(callData.length>0){
            bool success=Exec.call(mUserOp.sender,0,callData,callGasLimit);
            if(!success)mode=IPaymaster.PostOpMode.opReverted;
        }
        return _handlePostOp(0,mode,opInfo,context,preGas-gasleft()+opInfo.preOpGas);
    }}
    function getUserOpHash(UserOperation calldata userOp)public view returns(bytes32){
        return keccak256(abi.encode(userOp.hash(),address(this),block.chainid));
    }
    function _copyUserOpToMemory(UserOperation calldata userOp,MemoryUserOp memory mUserOp)internal pure{
        (mUserOp.sender,mUserOp.nonce,mUserOp.callGasLimit,mUserOp.verificationGasLimit,
            mUserOp.preVerificationGas,mUserOp.maxFeePerGas,mUserOp.maxPriorityFeePerGas)=
            (userOp.sender,userOp.nonce,userOp.callGasLimit,userOp.verificationGasLimit,
            userOp.preVerificationGas,userOp.maxFeePerGas,userOp.maxPriorityFeePerGas);
        bytes calldata paymasterAndData=userOp.paymasterAndData;
        if(paymasterAndData.length>0)mUserOp.paymaster=address(bytes20(paymasterAndData[:20]));
        else mUserOp.paymaster=address(0);
    }
    function simulateValidation(UserOperation calldata userOp)external{
        UserOpInfo memory outOpInfo;
        _simulationOnlyValidations(userOp);
        (uint validationData,uint paymasterValidationData)=_validatePrepayment(0,userOp,outOpInfo);
        (StakeInfo memory paymasterInfo,StakeInfo memory senderInfo)=
            (_getStakeInfo(outOpInfo.mUserOp.paymaster),_getStakeInfo(outOpInfo.mUserOp.sender));
        StakeInfo memory factoryInfo;
        bytes calldata initCode=userOp.initCode;
        address factory=initCode.length>=20?address(bytes20(initCode[0:20])):address(0);
        factoryInfo=_getStakeInfo(factory);
        ValidationData memory data=_intersectTimeRange(validationData,paymasterValidationData);
        address aggregator=data.aggregator;
        ReturnInfo memory returnInfo=ReturnInfo(outOpInfo.preOpGas,outOpInfo.prefund,
            aggregator==address(1),data.validAfter,data.validUntil,getMemoryBytesFromOffset(outOpInfo.contextOffset));
        if(aggregator!=address(0)&& aggregator!=address(1)){
            AggregatorStakeInfo memory aggregatorInfo=AggregatorStakeInfo(aggregator,_getStakeInfo(aggregator));
            revert ValidationResultWithAggregation(returnInfo,senderInfo,factoryInfo,paymasterInfo,aggregatorInfo);
        }
        revert ValidationResult(returnInfo,senderInfo,factoryInfo,paymasterInfo);
    }
    function _getRequiredPrefund(MemoryUserOp memory mUserOp)internal pure returns(uint){unchecked{
        uint requiredGas=mUserOp.callGasLimit+mUserOp.verificationGasLimit*(mUserOp.paymaster!=address(0)?3:1)
            +mUserOp.preVerificationGas;
        return requiredGas*mUserOp.maxFeePerGas;
    }}
    function _createSenderIfNeeded(uint opIndex,UserOpInfo memory opInfo,bytes calldata initCode)internal{
        if(initCode.length!=0){
            address sender=opInfo.mUserOp.sender;
            if(sender.code.length!=0)revert FailedOp(opIndex,"");
            address sender1=senderCreator.createSender{gas:opInfo.mUserOp.verificationGasLimit}(initCode);
            if(sender1==address(0))revert FailedOp(opIndex,"");
            if(sender1!=sender)revert FailedOp(opIndex,"");
            if(sender1.code.length==0)revert FailedOp(opIndex,"");
        }
    }
    function getSenderAddress(bytes calldata initCode)public{
        revert SenderAddressResult(senderCreator.createSender(initCode));
    }
    function _simulationOnlyValidations(UserOperation calldata userOp)internal view{
        try this._validateSenderAndPaymaster(userOp.initCode,userOp.sender,userOp.paymasterAndData){}
        catch Error(string memory revertReason){
            if(bytes(revertReason).length!=0)revert FailedOp(0,revertReason);
        }
    }
    function _validateSenderAndPaymaster(bytes calldata,address,bytes calldata)external pure{
        revert("");
    }
    function _validateAccountPrepayment(uint opIndex,UserOperation calldata op,UserOpInfo memory opInfo,uint requiredPrefund)
    internal returns(uint gasUsedByValidateAccountPrepayment,uint validationData){unchecked{
        (uint preGas,MemoryUserOp memory mUserOp)=(gasleft(),opInfo.mUserOp);
        address sender=mUserOp.sender;
        _createSenderIfNeeded(opIndex,opInfo,op.initCode);
        address paymaster=mUserOp.paymaster;
        numberMarker();
        uint missingAccountFunds=0;
        if(paymaster==address(0))missingAccountFunds=balanceOf(sender)>requiredPrefund?0:requiredPrefund-balanceOf(sender);
        try IAccount(sender).validateUserOp{gas:mUserOp.verificationGasLimit}(op,opInfo.userOpHash,missingAccountFunds)
        returns(uint _validationData){
            validationData=_validationData;
        }catch{
            revert FailedOp(opIndex,"");
        }
        if(paymaster==address(0)){
            if(requiredPrefund>deposits[sender].deposit)revert FailedOp(opIndex,"");
            deposits[sender].deposit=deposits[sender].deposit-requiredPrefund;
        }
        gasUsedByValidateAccountPrepayment=preGas-gasleft();
    }}
    function _validatePaymasterPrepayment(uint opIndex,UserOperation calldata op,UserOpInfo memory opInfo,uint requiredPreFund,
    uint gasUsedByValidateAccountPrepayment)internal returns(bytes memory context,uint validationData){unchecked{
        (uint gas,address paymaster)=(opInfo.mUserOp.verificationGasLimit-gasUsedByValidateAccountPrepayment,opInfo.mUserOp.paymaster);
        uint deposit=deposits[paymaster].deposit;
        if(deposit<requiredPreFund)revert FailedOp(opIndex,"");
        deposits[paymaster].deposit=deposit-requiredPreFund;
        try IPaymaster(paymaster).validatePaymasterUserOp{gas:gas}(op,opInfo.userOpHash,requiredPreFund)returns
        (bytes memory _context,uint _validationData){
            (context,validationData)=(_context,_validationData);
        }catch{
            revert FailedOp(opIndex,"");
        }
    }}
    function _validateAccountAndPaymasterValidationData(uint opIndex,uint validationData,uint paymasterValidationData,
    address expectedAggregator)internal view{
        (address aggregator,bool outOfTimeRange)=_getValidationData(validationData);
        if(expectedAggregator!=aggregator)revert FailedOp(opIndex,"");
        if(outOfTimeRange)revert FailedOp(opIndex,"");
        address pmAggregator;
        (pmAggregator,outOfTimeRange)=_getValidationData(paymasterValidationData);
        if(pmAggregator!=address(0))revert FailedOp(opIndex,"");
        if(outOfTimeRange)revert FailedOp(opIndex,"");
    }
    function _getValidationData(uint validationData)internal view returns(address aggregator,bool outOfTimeRange){
        if(validationData==0)return (address(0),false);
        ValidationData memory data=_parseValidationData(validationData);
        outOfTimeRange=block.timestamp>data.validUntil||block.timestamp<data.validAfter;
        aggregator=data.aggregator;
    }
    function _validatePrepayment(uint opIndex,UserOperation calldata userOp,UserOpInfo memory outOpInfo)
    private returns(uint validationData,uint paymasterValidationData){unchecked{
        (uint preGas,MemoryUserOp memory mUserOp)=(gasleft(),outOpInfo.mUserOp);
        _copyUserOpToMemory(userOp,mUserOp);
        outOpInfo.userOpHash=getUserOpHash(userOp);
        userOp.maxFeePerGas|userOp.maxPriorityFeePerGas;
        uint gasUsedByValidateAccountPrepayment;
        uint requiredPreFund=_getRequiredPrefund(mUserOp);
        (gasUsedByValidateAccountPrepayment,validationData)=_validateAccountPrepayment(opIndex,userOp,outOpInfo,requiredPreFund);
        numberMarker();
        bytes memory context;
        if(mUserOp.paymaster!=address(0))(context,paymasterValidationData)=
            _validatePaymasterPrepayment(opIndex,userOp,outOpInfo,requiredPreFund,gasUsedByValidateAccountPrepayment);
        if(userOp.verificationGasLimit<preGas-gasleft())revert FailedOp(opIndex,"");
        (outOpInfo.prefund,outOpInfo.contextOffset,outOpInfo.preOpGas)=
            (requiredPreFund,getOffsetOfMemoryBytes(context),preGas-gasleft()+userOp.preVerificationGas);
    }}
    function _handlePostOp(uint opIndex,IPaymaster.PostOpMode mode,UserOpInfo memory opInfo,bytes memory context,uint actualGas)
    private returns(uint actualGasCost){unchecked{
        (uint preGas,MemoryUserOp memory mUserOp)=(gasleft(),opInfo.mUserOp);
        address refundAddress;
        (uint gasPrice,address paymaster)=(getUserOpGasPrice(mUserOp),mUserOp.paymaster);
        if(paymaster==address(0))refundAddress=mUserOp.sender;
        else{
            refundAddress=paymaster;
            if(context.length>0){
                actualGasCost*=gasPrice;
                if(mode!=IPaymaster.PostOpMode.postOpReverted)
                    IPaymaster(paymaster).postOp{gas:mUserOp.verificationGasLimit}(mode,context,actualGasCost);
                else
                    try IPaymaster(paymaster).postOp{gas:mUserOp.verificationGasLimit}(mode,context,actualGasCost){}
                    catch{
                        revert FailedOp(opIndex,"");
                    }
            }
        }
        actualGasCost=actualGas+preGas-gasleft()*gasPrice;
        if(opInfo.prefund<actualGasCost)revert FailedOp(opIndex,"");
        _incrementDeposit(refundAddress,opInfo.prefund-actualGasCost);
    }}
    function getUserOpGasPrice(MemoryUserOp memory mUserOp)internal view returns(uint){unchecked{
        (uint maxFeePerGas,uint maxPriorityFeePerGas)=(mUserOp.maxFeePerGas,mUserOp.maxPriorityFeePerGas);
        if(maxFeePerGas==maxPriorityFeePerGas)return maxFeePerGas;
        return min(maxFeePerGas,maxPriorityFeePerGas+block.basefee);
    }}
    function min(uint a,uint b)internal pure returns(uint){
        return a<b?a:b;
    }
    function getOffsetOfMemoryBytes(bytes memory data)internal pure returns(uint offset){
        assembly{offset:=data}
    }
    function getMemoryBytesFromOffset(uint offset)internal pure returns(bytes memory data){
        assembly{data:=offset}
    }
    function numberMarker()internal view{
        assembly{mstore(0,number())}
    }
}