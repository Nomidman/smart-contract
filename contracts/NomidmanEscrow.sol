pragma solidity v0.4.25;

contract NomidmanEscrow {

    address public mediator;
    address public relayer;
    address public manager;

    uint8 constant DISPUTE_CODE = 0x01;

    struct Escrow {
        bool exists;
    }

    constructor () public {
        owner = msg.sender;
        arbitrator = msg.sender;
        relayer = msg.sender;
        manager = msg.sender;
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
        byte16 _tradeId,
        address seller,
        address buyer,
        uint256 value,
        uint16 _fee
    ) view internal returns (byte32)
    {
        bytes32 tradeHash = keccak256(_tradeID, _seller, _buyer, _value, _fee);
        return (tradeHash);
    }
}