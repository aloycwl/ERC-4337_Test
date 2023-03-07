pragma solidity>0.8.0;//SPDX-License-Identifier:None

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