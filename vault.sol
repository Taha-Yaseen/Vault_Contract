// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.0.0/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.0.0/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.0.0/contracts/token/ERC20/IERC20.sol";

contract TahaCoin is ERC20, Ownable {
    constructor() ERC20("TAHA", "THA") {
        _mint(msg.sender, 4000 * 10**decimals());
    }

    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}

contract Vault is Ownable {
    struct Payment {
        uint256 paymentId;
        address spender;
        address recipient;
        uint256 amount;
        bool paid;
        bool canceled;
        uint256 earliestPayTime;
        uint256 securityGuardDelay;
        bool eth;
    }

    IERC20 public token;

    uint256 nonce = 0;
    uint256 private totalSupply;
    uint256 minimumTimeDelay;

    mapping(address => bool) private whiteList;
    mapping(uint256 => Payment) private payments;

    event DepositMade(address _address, uint256 _amount, string _currencyType);
    event PaymentCreated(
        uint256 _id,
        address _recipient,
        uint256 _amount,
        uint256 _payTime,
        bool _eth
    );
    event PaymentCollected(
        address _recipient,
        uint256 _amount,
        uint256 _payTime,
        bool _eth
    );
    event PaymentCanceled(uint256 _id);

    modifier onlyApprovedSpender() {
        require(whiteList[msg.sender], "You are not authorized");
        _;
    }

    modifier onlyRecipient(uint256 _paymentId) {
        require(
            payments[_paymentId].recipient == msg.sender,
            "You are not authorized"
        );
        _;
    }

    constructor(address _tokenAddress, uint256 _minimumTimeDelay) {
        token = IERC20(_tokenAddress);
        minimumTimeDelay = block.timestamp + _minimumTimeDelay;
    }

    function approveSpender(address _spender) public onlyOwner {
        whiteList[_spender] = true;
    }

    function getTotalSupply() public view returns (uint256) {
        return address(this).balance;
    }

    function deposit(uint256 _amount) public payable {
        require(
            _amount > 0,
            "To make a deposit the amount has to be greater than 0"
        );

        totalSupply += _amount;

        bool sent = token.transferFrom(msg.sender, address(this), _amount);
        require(sent, "Failed to send tokens");

        emit DepositMade(msg.sender, _amount, "token");
    }

    receive() external payable {
        emit DepositMade(msg.sender, msg.value, "ether");
    }

    fallback() external payable {
        emit DepositMade(msg.sender, msg.value, "ether");
    }

    function createPayment(
        bool _eth,
        address _recipient,
        uint256 _amount,
        uint256 _earliestPayTime,
        uint256 _securityGuard
    ) public payable onlyApprovedSpender {
        require(
            _amount > 0,
            "To make a deposit the amount has to be greater than 0"
        );
        require(
            _recipient != msg.sender,
            "Recipient can't be the same as the sender"
        );
        if (!_eth) {
            require(
                _amount <= totalSupply,
                "There is not enough amount in the vault"
            );
        }

        nonce++;

        uint256 id = uint256(
            keccak256(
                abi.encodePacked(msg.sender, _amount, nonce, block.timestamp)
            )
        );
        _earliestPayTime = block.timestamp + _earliestPayTime >=
            minimumTimeDelay
            ? _earliestPayTime + block.timestamp
            : minimumTimeDelay;

        payments[id] = Payment(
            id,
            msg.sender,
            _recipient,
            _eth ? _amount * 10**18 : _amount,
            false,
            false,
            _earliestPayTime,
            _securityGuard,
            _eth
        );

        emit PaymentCreated(
            id,
            payments[id].recipient,
            payments[id].amount,
            _earliestPayTime,
            _eth
        );
    }

    function collectAuthorizedPayment(uint256 _paymentId)
        public
        payable
        onlyRecipient(_paymentId)
    {
        //Security Guard option
        if (payments[_paymentId].paymentId < 0) {
            payments[_paymentId].earliestPayTime =
                block.timestamp +
                payments[_paymentId].earliestPayTime +
                payments[_paymentId].securityGuardDelay;
        }
        require(!payments[_paymentId].canceled, "The payment is canceled");
        require(!payments[_paymentId].paid, "The payment is already paid");
        require(
            payments[_paymentId].earliestPayTime <= block.timestamp,
            "You cant collect your payment yet"
        );

        if (payments[_paymentId].eth) {
            require(
                payments[_paymentId].amount <= address(this).balance,
                "There is not enough amount in the vault"
            );
            (bool sent, ) = payments[_paymentId].recipient.call{
                value: payments[_paymentId].amount
            }("");
            require(sent, "Failed to deposit eth");
        } else {
            require(
                payments[_paymentId].amount <= totalSupply,
                "There is not enough amount in the vault"
            );
            bool sent = token.transfer(
                payments[_paymentId].recipient,
                payments[_paymentId].amount
            );
            require(sent, "Failed to collect the payment");
            totalSupply -= payments[_paymentId].amount;
        }
        payments[_paymentId].paid = true;
        emit PaymentCollected(
            payments[_paymentId].recipient,
            payments[_paymentId].amount,
            payments[_paymentId].earliestPayTime,
            payments[_paymentId].eth
        );
    }

    function cancelPayment(uint256 _paymentId) public onlyOwner {
        require(payments[_paymentId].paymentId > 0, "Payment not found");
        payments[_paymentId].canceled = true;
        emit PaymentCanceled(_paymentId);
    }

    function setMinimumTimeDelay(uint256 _newMinTimeDelay) public onlyOwner {
        minimumTimeDelay = _newMinTimeDelay;
    }
}
