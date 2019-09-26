pragma solidity ^0.5.0;

/**
 * @title SafeMath
 * @dev Math operations with safety checks that revert on error
 */
library SafeMath {

    /**
    * @dev Multiplies two numbers, reverts on overflow.
    */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b);

        return c;
    }

    /**
    * @dev Integer division of two numbers truncating the quotient, reverts on division by zero.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0); // Solidity only automatically asserts when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
    * @dev Subtracts two numbers, reverts on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;

        return c;
    }

    /**
    * @dev Adds two numbers, reverts on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);

        return c;
    }

    /**
    * @dev Divides two numbers and returns the remainder (unsigned integer modulo),
    * reverts when dividing by zero.
    */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
    }
}

contract NomidmanEscrow {

    using SafeMath for uint128;
    using SafeMath for uint256;

    address public mediator;
    address public relayer;
    address public manager;
    uint256 public nomidFees;

    uint8 constant DISPUTE_CODE = 0x01;
    uint8 constant RELEASE_CODE = 0x02;
    uint8 constant CANCELLED_BY_SELLER_CODE = 0x03;
    uint8 constant CANCELLED_BY_BUYER_CODE = 0x04;
    uint8 constant SELLER_CANCEL_PROHIBITED_CODE = 0x05;
    uint8 constant CANCEL_REQUEST_BY_SELLER_CODE = 0x06;

    event Created(bytes32 _tradeHash);
    event SellerCancelDisabled(bytes32 _tradeHash);
    event SellerRequestedCancel(bytes32 _tradeHash);
    event CancelledBySeller(bytes32 _tradeHash);
    event CancelledByBuyer(bytes32 _tradeHash);
    event Released(bytes32 _tradeHash);
    event DisputeResolved(bytes32 _tradeHash);

    event AmountCheck(uint256 sent, uint256 value);

    event EscrowCheck(bytes16 _tradeID, address _seller, address _buyer, uint256 _value,
        uint256 _fee);

    event Test1(uint256 _gasFees);
    event Test2(uint256 _totalFeesl);
    event TestRelease(uint8);
    event TestRelease2(address);

    struct Escrow {
        bool exists;
        uint32 canBeCancelledBySellerWithin;
        uint128 relayerGasBalance;
    }

    enum GasSpendingAction {RELEASE, DISABLE_SELLER_CANCEL,
        BUYER_CANCEL, SELLER_CANCEL, SELLER_CANCEL_REQUEST, RESOLVE_DISPUTE, BATCH_RELAY}

    mapping(bytes32 => uint128) gasEstimations;

    constructor () public {
        manager = msg.sender;
        mediator = msg.sender;
        relayer = 0xe525202E1672B88e58e88D82E2cd369351E5C57c;

        gasEstimations[keccak256(abi.encodePacked(GasSpendingAction.RELEASE))] = 36100;
        gasEstimations[keccak256(abi.encodePacked(GasSpendingAction.DISABLE_SELLER_CANCEL))] = 12100;
        gasEstimations[keccak256(abi.encodePacked(GasSpendingAction.BUYER_CANCEL))] = 36100;
        gasEstimations[keccak256(abi.encodePacked(GasSpendingAction.SELLER_CANCEL))] = 36100;
        gasEstimations[keccak256(abi.encodePacked(GasSpendingAction.SELLER_CANCEL_REQUEST))] = 12100;
        gasEstimations[keccak256(abi.encodePacked(GasSpendingAction.RESOLVE_DISPUTE))] = 36100;
        gasEstimations[keccak256(abi.encodePacked(GasSpendingAction.BATCH_RELAY))] = 28500;
    }

    mapping(bytes32 => Escrow) public escrows;
    bytes32[] public escrowLUTTemp;

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
        uint256 _fee
    ) pure public returns (bytes32)
    {
        bytes32 tradeHash = keccak256(abi.encodePacked(_tradeId, _seller, _buyer, _value, _fee));
        return (tradeHash);
    }

    function createEscrow(bytes16 _tradeID, address _seller, address _buyer, uint256 _value,
        uint256 _fee, uint32 _paymentWindowInSeconds, uint256 _expiry, uint8 _v, bytes32 _r, bytes32 _s)
    payable external{
        uint256 amount = msg.value;
        bytes32 _tradeHash = keccak256(abi.encodePacked(_tradeID, _seller, _buyer, _value, _fee));
        bytes32 combinedhash = keccak256(abi.encodePacked(_tradeHash, _paymentWindowInSeconds));
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHash = keccak256(abi.encodePacked(prefix, combinedhash));

        require(!escrows[_tradeHash].exists);
        require(ecrecover(prefixedHash, _v, _r, _s) == relayer);
        //require(block.timestamp < _expiry);
        require(msg.value > 0 && msg.value == _value);
        uint32 canBeCancelledBySellerWithin = _paymentWindowInSeconds == 0 ? 1 : uint32(block.timestamp) + _paymentWindowInSeconds;
        escrows[_tradeHash] = Escrow(true, canBeCancelledBySellerWithin, 0);
        escrowLUTTemp.push(_tradeHash);
        emit Created(_tradeHash);
    }

    function withdrawFees(uint256 _amount, address payable _receiver) public onlyManager {
        require(_amount <= nomidFees);
        nomidFees = nomidFees.sub(_amount);
        _receiver.transfer(_amount);
    }

    function doRelease(bytes16 _tradeID, address payable _seller, address payable _buyer, uint256 _value, uint256 _fee, uint128 _additionalGas) private returns (bool) {
        bytes32 _tradeHash = getTradeHash(_tradeID, _seller, _buyer, _value, _fee);
        Escrow storage _escrow = escrows[_tradeHash];
        if (!_escrow.exists) return false;

        uint128 _gasFees = uint128(_escrow.relayerGasBalance.add(msg.sender == relayer
            ? gasEstimations[keccak256(abi.encodePacked(GasSpendingAction.RELEASE))].add(_additionalGas).mul(uint128(tx.gasprice))
            : 0));

        delete escrows[_tradeHash];

        emit Released(_tradeHash);
        transferMinusFees(_buyer, _value, _gasFees, _fee);

        return true;
    }

    function doDisableSellerCancel(bytes16 _tradeID, address _seller, address _buyer, uint256 _value, uint256 _fee, uint128 _additionalGas)
    private returns (bool) {
        bytes32 _tradeHash = getTradeHash(_tradeID, _seller, _buyer, _value, _fee);
        Escrow memory _escrow = escrows[_tradeHash];
        if (!_escrow.exists) return false;
        if (_escrow.canBeCancelledBySellerWithin == 0) return false;
        escrows[_tradeHash].canBeCancelledBySellerWithin = 0;
        emit SellerCancelDisabled(_tradeHash);
        if (msg.sender == relayer) {
            increaseGasSpent(_tradeHash,
                gasEstimations[keccak256(abi.encodePacked(GasSpendingAction.DISABLE_SELLER_CANCEL))] + _additionalGas);
        }
        return true;
    }

    function doBuyerCancel(bytes16 _tradeID, address payable _seller, address payable _buyer, uint256 _value, uint256 _fee, uint128 _additionalGas)
    private returns (bool) {
        bytes32 _tradeHash = getTradeHash(_tradeID, _seller, _buyer, _value, _fee);
        Escrow storage _escrow = escrows[_tradeHash];

        if (!_escrow.exists) return false;

        uint128 _gasFees = uint128(_escrow.relayerGasBalance.add(msg.sender == relayer
            ? gasEstimations[keccak256(abi.encodePacked(GasSpendingAction.BUYER_CANCEL))].add(_additionalGas).mul(uint128(tx.gasprice))
            : 0));

        delete escrows[_tradeHash];
        emit CancelledByBuyer(_tradeHash);
        transferMinusFees(_seller, _value, _gasFees, 0);
        return true;
    }

    function doSellerCancel(bytes16 _tradeID, address payable _seller, address payable _buyer, uint256 _value, uint256 _fee, uint128 _additionalGas)
    private returns (bool) {
        bytes32 _tradeHash = getTradeHash(_tradeID, _seller, _buyer, _value, _fee);

        Escrow storage _escrow = escrows[_tradeHash];

        if (!_escrow.exists) return false;

        if (_escrow.canBeCancelledBySellerWithin <= 1 || _escrow.canBeCancelledBySellerWithin > block.timestamp)
        {
            return false;
        }

        uint128 _gasFees = uint128(_escrow.relayerGasBalance.add(msg.sender == relayer
            ? gasEstimations[keccak256(abi.encodePacked(GasSpendingAction.SELLER_CANCEL))].add(_additionalGas).mul(uint128(tx.gasprice))
            : 0));

        delete escrows[_tradeHash];

        emit CancelledBySeller(_tradeHash);

        transferMinusFees(_seller, _value, _gasFees, 0);

        return true;
    }

    function doSellerRequestCancel(bytes16 _tradeID, address _seller, address _buyer, uint256 _value, uint256 _fee, uint128 _additionalGas)
    private returns (bool) {
        bytes32 _tradeHash = getTradeHash(_tradeID, _seller, _buyer, _value, _fee);

        Escrow storage _escrow = escrows[_tradeHash];

        if (!_escrow.exists) return false;

        if (_escrow.canBeCancelledBySellerWithin != 1)
        {
            return false;
        }

        escrows[_tradeHash].canBeCancelledBySellerWithin = uint32(block.timestamp) + 3600;

        emit SellerRequestedCancel(_tradeHash);

        if (msg.sender == relayer) {
            increaseGasSpent(_tradeHash, gasEstimations[keccak256(abi.encodePacked(GasSpendingAction.SELLER_CANCEL_REQUEST))] + _additionalGas);
        }

        return true;
    }

    function resolveDispute(bytes16 _tradeID, address payable _seller, address payable _buyer, uint256 _value, uint16 _fee, uint8 _v, bytes32 _r, bytes32 _s, uint8 _buyerPercent)
    external onlyMediator {
        address _signature = ecrecover(keccak256(abi.encodePacked(_tradeID, DISPUTE_CODE)), _v, _r, _s);
        require(_signature == _buyer || _signature == _seller);

        bytes32 _tradeHash = getTradeHash(_tradeID, _seller, _buyer, _value, _fee);

        Escrow storage _escrow = escrows[_tradeHash];

        require(_escrow.exists);
        require(_buyerPercent <= 100);

        uint256 _totalFees = _escrow.relayerGasBalance + gasEstimations[keccak256(abi.encodePacked(GasSpendingAction.RESOLVE_DISPUTE))];
        require(_value - _totalFees <= _value);
        // Prevent underflow
        nomidFees += _totalFees;
        delete escrows[_tradeHash];
        emit DisputeResolved(_tradeHash);
        _buyer.transfer((_value - _totalFees) * _buyerPercent / 100);
        _seller.transfer((_value - _totalFees) * (100 - _buyerPercent) / 100);
    }

    function release(bytes16 _tradeID, address payable _seller, address payable _buyer, uint256 _value, uint256 _fee) external returns (bool){
        require(msg.sender == _seller);
        return doRelease(_tradeID, _seller, _buyer, _value, _fee, 0);
    }

    function disableSellerCancel(bytes16 _tradeID, address _seller, address _buyer, uint256 _value, uint16 _fee) external returns (bool) {
        require(msg.sender == _buyer);
        return doDisableSellerCancel(_tradeID, _seller, _buyer, _value, _fee, 0);
    }

    function buyerCancel(bytes16 _tradeID, address payable _seller, address payable _buyer, uint256 _value, uint16 _fee) external returns (bool) {
        require(msg.sender == _buyer);
        return doBuyerCancel(_tradeID, _seller, _buyer, _value, _fee, 0);
    }

    function sellerCancel(bytes16 _tradeID, address payable _seller, address payable _buyer, uint256 _value, uint16 _fee) external returns (bool) {
        require(msg.sender == _seller);
        return doSellerCancel(_tradeID, _seller, _buyer, _value, _fee, 0);
    }

    function sellerRequestCancel(bytes16 _tradeID, address payable _seller, address payable _buyer, uint256 _value, uint16 _fee) external returns (bool) {
        require(msg.sender == _seller);
        return doSellerRequestCancel(_tradeID, _seller, _buyer, _value, _fee, 0);
    }

    function relaySellerCannotCancel(bytes16 _tradeID, address payable _seller, address payable _buyer, uint256 _value, uint16 _fee, uint8 _v, bytes32 _r, bytes32 _s) external returns (bool) {
        return relay(_tradeID, _seller, _buyer, _value, _fee, _v, _r, _s, SELLER_CANCEL_PROHIBITED_CODE, 0);
    }

    function relayBuyerCancel(bytes16 _tradeID, address payable _seller, address payable _buyer, uint256 _value, uint16 _fee, uint8 _v, bytes32 _r, bytes32 _s) external returns (bool) {
        return relay(_tradeID, _seller, _buyer, _value, _fee, _v, _r, _s, CANCELLED_BY_BUYER_CODE, 0);
    }

    function relayRelease(bytes16 _tradeID, address payable _seller, address payable _buyer, uint256 _value, uint256 _fee, uint8 _v, bytes32 _r, bytes32 _s) external returns (bool) {
        return relay(_tradeID, _seller, _buyer, _value, _fee, _v, _r, _s, RELEASE_CODE, 0);
    }

    function relaySellerCancel(bytes16 _tradeID, address payable _seller, address payable _buyer, uint256 _value, uint16 _fee, uint8 _v, bytes32 _r, bytes32 _s) external returns (bool) {
        return relay(_tradeID, _seller, _buyer, _value, _fee, _v, _r, _s, CANCELLED_BY_SELLER_CODE, 0);
    }

    function relaySellerRequestCancel(bytes16 _tradeID, address payable _seller, address payable _buyer, uint256 _value, uint16 _fee, uint8 _v, bytes32 _r, bytes32 _s) external returns (bool) {
        return relay(_tradeID, _seller, _buyer, _value, _fee, _v, _r, _s, CANCEL_REQUEST_BY_SELLER_CODE, 0);
    }

    function relay(bytes16 _tradeID, address payable _seller, address payable _buyer, uint256 _value, uint256 _fee, uint8 _v, bytes32 _r, bytes32 _s, uint8 _actionByte, uint128 _additionalGas)
    private returns (bool) {
        address _relayedSender = getRelayedSender(_tradeID, _actionByte, _v, _r, _s);
        if (_relayedSender == _buyer) {
            if (_actionByte == SELLER_CANCEL_PROHIBITED_CODE) {
                return doDisableSellerCancel(_tradeID, _seller, _buyer, _value, _fee, _additionalGas);
            } else if (_actionByte == CANCELLED_BY_BUYER_CODE) {
                return doBuyerCancel(_tradeID, _seller, _buyer, _value, _fee, _additionalGas);
            }
        } else if (_relayedSender == _seller) {
            if (_actionByte == RELEASE_CODE) {
                return doRelease(_tradeID, _seller, _buyer, _value, _fee, _additionalGas);
            } else if (_actionByte == CANCELLED_BY_SELLER_CODE) {
                return doSellerCancel(_tradeID, _seller, _buyer, _value, _fee, _additionalGas);
            } else if (_actionByte == CANCEL_REQUEST_BY_SELLER_CODE) {
                return doSellerRequestCancel(_tradeID, _seller, _buyer, _value, _fee, _additionalGas);
            }
        } else {
            return false;
        }
    }

    function batchRelay(bytes16[] memory _tradeID, address payable[] memory _seller, address payable[] memory _buyer, uint256[] memory _value, uint16[] memory _fee, uint8[] memory _v, bytes32[] memory _r, bytes32[] memory _s, uint8[] memory _actionByte) public returns (bool[] memory) {
        bool[] memory _results = new bool[](_tradeID.length);
        uint128 _additionalGas = uint128(msg.sender == relayer
            ? gasEstimations[keccak256(abi.encodePacked(GasSpendingAction.BATCH_RELAY))] / _tradeID.length
            : 0);
        for (uint8 i = 0; i < _tradeID.length; i++) {
            _results[i] = relay(_tradeID[i], _seller[i], _buyer[i], _value[i], _fee[i], _v[i], _r[i], _s[i], _actionByte[i], _additionalGas);
        }
        return _results;
    }

    function getRelayedSender(bytes16 _tradeID, uint8 _actionByte, uint8 _v, bytes32 _r, bytes32 _s) pure private returns (address) {
        bytes32 _hash = keccak256(abi.encodePacked(_tradeID, _actionByte));
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHash = keccak256(abi.encodePacked(prefix, _hash));
        //if (tx.gasprice > _maximumGasPrice) return address(0);
        return ecrecover(prefixedHash, _v, _r, _s);
    }

    function transferMinusFees(address payable _to, uint256 _value, uint128 _totalGasFeesSpentByRelayer, uint256 _fee) private {
        uint256 _totalFees = _fee.add(_totalGasFeesSpentByRelayer);
        emit Test1(_totalFees);
        if (_value.sub(_totalFees) > _value) return;
        nomidFees = nomidFees.add(_totalFees);
        emit Test2(_value.sub(_totalFees));
        _to.transfer(_value.sub(_totalFees));
    }

    function increaseGasSpent(bytes32 _tradeHash, uint128 _gas) private {
        escrows[_tradeHash].relayerGasBalance += _gas * uint128(tx.gasprice);
    }

    function setArbitrator(address _newMediator) onlyManager external {
        mediator = _newMediator;
    }

    function setManager(address _newManager) onlyManager external {
        manager = _newManager;
    }

    function setRelayer(address _newRelayer) onlyManager external {
        relayer = _newRelayer;
    }
}