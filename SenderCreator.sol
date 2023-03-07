pragma solidity>0.8.0;//SPDX-License-Identifier:None

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