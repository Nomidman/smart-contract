pragma solidity ^0.4.25;

contract NomidmanEscrow {

    address public mediator;
    address public relayer;
    address public manager;

    uint8 constant DISPUTE_CODE = 0x01;

    struct Escrow {
        bool exists;
    }

    constructor () public {
        manager = msg.sender;
        mediator = msg.sender;
        relayer = msg.sender;
    }

    mapping (bytes32 => Escrow) public escrows;

    modifier onlyManager() {
        require(msg.sender == manager);
        _;
    }

    modifier onlyMediator() {
        require(msg.sender == mediator);
        _;
    }

    // Calculate unique hash for trade
    function getTradeHash(
        bytes16 _tradeId,
        address _seller,
        address _buyer,
        uint256 _value,
        uint16 _fee
    ) pure internal returns (bytes32)
    {
        bytes32 tradeHash = keccak256(abi.encodePacked(_tradeId, _seller, _buyer, _value, _fee));
        return (tradeHash);
    }

    function createEscrow(bytes16 _tradeID, address _seller, address _buyer, uint256 _value,
        uint16 _fee, uint32 _paymentWindowInSeconds, uint8 _v, bytes32 _r, bytes32 _s) payable external {
        bytes32 _tradeHash = keccak256(abi.encodePacked(_tradeID, _seller, _buyer, _value, _fee));
        require(!escrows[_tradeHash].exists);
        require(ecrecover(keccak256(abi.encodePacked(_tradeHash, _paymentWindowInSeconds)), _v, _r, _s) == relayer);
    }
}