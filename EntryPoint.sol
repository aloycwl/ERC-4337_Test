pragma solidity>0.8.0;//SPDX-License-Identifier:None

import"Interfaces.sol";
import"Helpers.sol";

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
        //require(beneficiary!=address(0));
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
        for (uint i=0;i<opslen;i++){
            UserOpInfo memory opInfo=opInfos[i];
            (uint validationData,uint pmValidationData)=_validatePrepayment(i,ops[i],opInfo);
            _validateAccountAndPaymasterValidationData(i,validationData,pmValidationData,address(0));
        }
        uint collected=0;
        for(uint i=0;i<opslen;i++)collected+=_executeUserOp(i,ops[i],opInfos[i]);
        _compensate(beneficiary,collected);
    }}
    function handleAggregatedOps(UserOpsPerAggregator[]calldata opsPerAggregator,address payable beneficiary)public{
        (uint opasLen,uint totalOps)=(opsPerAggregator.length,0);
        for (uint i=0;i<opasLen;i++){
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
        for (uint a=0;a<opasLen;a++){
            UserOpsPerAggregator calldata opa=opsPerAggregator[a];
            UserOperation[]calldata ops=opa.userOps;
            IAggregator aggregator=opa.aggregator;
            uint opslen=ops.length;
            for (uint i=0;i<opslen;i++){
                UserOpInfo memory opInfo=opInfos[opIndex];
                (uint validationData,uint paymasterValidationData)=_validatePrepayment(opIndex,ops[i],opInfo);
                _validateAccountAndPaymasterValidationData(i,validationData,paymasterValidationData,address(aggregator));
                opIndex++;
            }
        }
        uint collected=0;
        opIndex=0;
        for (uint a=0;a<opasLen;a++){
            UserOpsPerAggregator calldata opa=opsPerAggregator[a];
            emit SignatureAggregatorChanged(address(opa.aggregator));
            UserOperation[]calldata ops=opa.userOps;
            uint opslen=ops.length;
            for (uint i=0;i<opslen;i++){
                collected+=_executeUserOp(opIndex,ops[i],opInfos[opIndex]);
                opIndex++;
            }
        }
        _compensate(beneficiary,collected);
    }
    function simulateHandleOp(UserOperation calldata op,address target,bytes calldata targetCallData)external override{
        UserOpInfo memory opInfo;
        _simulationOnlyValidations(op);
        (uint validationData,uint paymasterValidationData)=_validatePrepayment(0,op,opInfo);
        ValidationData memory data=_intersectTimeRange(validationData,paymasterValidationData);
        numberMarker();
        uint paid=_executeUserOp(0,op,opInfo);
        numberMarker();
        bool targetSuccess;
        bytes memory targetResult;
        if(target!=address(0))(targetSuccess,targetResult)=target.call(targetCallData);
        revert ExecutionResult(opInfo.preOpGas,paid,data.validAfter,data.validUntil,targetSuccess,targetResult);
    }
    function innerHandleOp(bytes memory callData,UserOpInfo memory opInfo,bytes calldata context)external returns(uint actualGasCost){
        uint preGas=gasleft();
        //require(msg.sender==address(this));
        MemoryUserOp memory mUserOp=opInfo.mUserOp;
        uint callGasLimit=mUserOp.callGasLimit;
        unchecked{
            if(gasleft()<callGasLimit+mUserOp.verificationGasLimit+5000){
                assembly{
                    mstore(0,INNER_OUT_OF_GAS)
                    revert(0,32)
                }
            }
        }
        IPaymaster.PostOpMode mode=IPaymaster.PostOpMode.opSucceeded;
        if(callData.length>0){
            bool success=Exec.call(mUserOp.sender,0,callData,callGasLimit);
            if(!success)mode=IPaymaster.PostOpMode.opReverted;
        }
        unchecked{
            uint actualGas=preGas-gasleft()+opInfo.preOpGas;
            return _handlePostOp(0,mode,opInfo,context,actualGas);
        }
    }
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
        bool sigFailed=aggregator==address(1);
        ReturnInfo memory returnInfo=ReturnInfo(outOpInfo.preOpGas,outOpInfo.prefund,
            sigFailed,data.validAfter,data.validUntil,getMemoryBytesFromOffset(outOpInfo.contextOffset));
        if(aggregator!=address(0)&& aggregator!=address(1)){
            AggregatorStakeInfo memory aggregatorInfo=AggregatorStakeInfo(aggregator,_getStakeInfo(aggregator));
            revert ValidationResultWithAggregation(returnInfo,senderInfo,factoryInfo,paymasterInfo,aggregatorInfo);
        }
        revert ValidationResult(returnInfo,senderInfo,factoryInfo,paymasterInfo);
    }
    function _getRequiredPrefund(MemoryUserOp memory mUserOp)internal pure returns(uint requiredPrefund){unchecked{
        uint mul=mUserOp.paymaster!=address(0)?3:1;
        uint requiredGas=mUserOp.callGasLimit+mUserOp.verificationGasLimit*mul+mUserOp.preVerificationGas;
        requiredPrefund=requiredGas*mUserOp.maxFeePerGas;
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
        }catch Error(string memory){
            revert FailedOp(opIndex,"");
        }catch{
            revert FailedOp(opIndex,"");
        }
        if(paymaster==address(0)){
            DepositInfo storage senderInfo=deposits[sender];
            uint deposit=senderInfo.deposit;
            if(requiredPrefund>deposit)revert FailedOp(opIndex,"");
            senderInfo.deposit=uint112(deposit-requiredPrefund);
        }
        gasUsedByValidateAccountPrepayment=preGas-gasleft();
    }}
    function _validatePaymasterPrepayment(uint opIndex,UserOperation calldata op,UserOpInfo memory opInfo,uint requiredPreFund,
    uint gasUsedByValidateAccountPrepayment)internal returns(bytes memory context,uint validationData){unchecked{
        MemoryUserOp memory mUserOp=opInfo.mUserOp;
        uint verificationGasLimit=mUserOp.verificationGasLimit;
        //require(verificationGasLimit>gasUsedByValidateAccountPrepayment);
        (uint gas,address paymaster)=(verificationGasLimit-gasUsedByValidateAccountPrepayment,mUserOp.paymaster);
        DepositInfo storage paymasterInfo=deposits[paymaster];
        uint deposit=paymasterInfo.deposit;
        if(deposit<requiredPreFund)revert FailedOp(opIndex,"");
        paymasterInfo.deposit=uint112(deposit-requiredPreFund);
        try IPaymaster(paymaster).validatePaymasterUserOp{gas:gas}(op,opInfo.userOpHash,requiredPreFund)returns
        (bytes memory _context,uint _validationData){
            (context,validationData)=(_context,_validationData);
        }catch Error(string memory){
            revert FailedOp(opIndex,"");
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
    private returns(uint validationData,uint paymasterValidationData){
        (uint preGas,MemoryUserOp memory mUserOp)=(gasleft(),outOpInfo.mUserOp);
        _copyUserOpToMemory(userOp,mUserOp);
        outOpInfo.userOpHash=getUserOpHash(userOp);
        //uint maxGasValues=mUserOp.preVerificationGas|mUserOp.verificationGasLimit|mUserOp.callGasLimit|
        userOp.maxFeePerGas|userOp.maxPriorityFeePerGas;
        //require(maxGasValues<=type(uint120).max);
        uint gasUsedByValidateAccountPrepayment;
        uint requiredPreFund=_getRequiredPrefund(mUserOp);
        (gasUsedByValidateAccountPrepayment,validationData)=_validateAccountPrepayment(opIndex,userOp,outOpInfo,requiredPreFund);
        numberMarker();
        bytes memory context;
        if(mUserOp.paymaster!=address(0))(context,paymasterValidationData)=
            _validatePaymasterPrepayment(opIndex,userOp,outOpInfo,requiredPreFund,gasUsedByValidateAccountPrepayment);
        unchecked{
            uint gasUsed=preGas-gasleft();
            if(userOp.verificationGasLimit<gasUsed)revert FailedOp(opIndex,"");
            (outOpInfo.prefund,outOpInfo.contextOffset,outOpInfo.preOpGas)=
                (requiredPreFund,getOffsetOfMemoryBytes(context),preGas-gasleft()+userOp.preVerificationGas);
        }
    }
    function _handlePostOp(uint opIndex,IPaymaster.PostOpMode mode,UserOpInfo memory opInfo,bytes memory context,uint actualGas)
    private returns(uint actualGasCost){unchecked{
        (uint preGas,MemoryUserOp memory mUserOp)=(gasleft(),opInfo.mUserOp);
        address refundAddress;
        (uint gasPrice,address paymaster)=(getUserOpGasPrice(mUserOp),mUserOp.paymaster);
        if(paymaster==address(0))refundAddress=mUserOp.sender;
        else{
            refundAddress=paymaster;
            if(context.length>0){
                actualGasCost=actualGas*gasPrice;
                if(mode!=IPaymaster.PostOpMode.postOpReverted)
                    IPaymaster(paymaster).postOp{gas:mUserOp.verificationGasLimit}(mode,context,actualGasCost);
                else
                    try IPaymaster(paymaster).postOp{gas:mUserOp.verificationGasLimit}(mode,context,actualGasCost){}
                    catch{
                        revert FailedOp(opIndex,"");
                    }
            }
        }
        actualGas+=preGas-gasleft();
        actualGasCost=actualGas*gasPrice;
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