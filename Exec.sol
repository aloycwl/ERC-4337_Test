pragma solidity>0.8.0;//SPDX-License-Identifier:None

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