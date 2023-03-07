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
    function hash(UserOperation calldata userOp)internal pure returns(bytes32) {
        return keccak256(pack(userOp));
    }
    function min(uint a,uint b)internal pure returns(uint){
        return a<b?a:b;
    }
}