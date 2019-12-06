/**
 *Submitted for verification at Etherscan.io on 2019-09-23
*/

pragma solidity ^0.5.13;


contract PriceOracles {
    struct Price {
        uint price;
        uint  expiration;
    }
    address public admin;
    mapping (address => Price) public oracleMap;

    constructor () public {
        admin = msg.sender;
    }

    //验证合约的操作是否被授权.
    modifier onlyAdmin {
        require(msg.sender == admin, "require admin");
        _;
    }

    function setAdmin(address newAdmin) public onlyAdmin {
        admin = newAdmin;
    }

    function getExpiration(address token) public view returns (uint) {
        return oracleMap[token].expiration;
    }

    function getPrice(address token) public view returns (uint) {
        return oracleMap[token].price;
    }

    function get(address token) public view returns (uint, bool) {
        return (oracleMap[token].price, valid(token));
    }

    function valid(address token) public view returns (bool) {
        return now < oracleMap[token].expiration;
    }

    // 设置价格为 @val, 保持有效时间为 @exp second.
    function set(address token, uint val, uint exp) public onlyAdmin
    {
        oracleMap[token].price = val;
        oracleMap[token].expiration = now + exp;
    }
}