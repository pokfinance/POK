pragma solidity 0.5.16;

import "./lib/SafeMath.sol";
import "./lib/SafeERC20.sol";
import "./lib/Ownable.sol";

contract POKLPWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public uni_lp;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        uni_lp.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public {
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        uni_lp.safeTransfer(msg.sender, amount);
    }
}

/**
 * POKPool
 */
pragma solidity 0.5.16;

contract POKWETHPool is POKLPWrapper, Ownable {
    constructor(
        address pokToken_,
        address reserveToken_,
        address uniswap_factory
    ) public {
        (address token0, address token1) = sortTokens(pokToken_, reserveToken_);

        // used for interacting with uniswap
        if (token0 == pokToken_) {
            isToken0 = true;
        } else {
            isToken0 = false;
        }

        uniswap_pair = pairFor(uniswap_factory, token0, token1);

        uni_lp = IERC20(uniswap_pair);
    }

    address public uniswap_pair;

    bool public isToken0;
    uint256 private constant stakeMax = 10000;
    uint256 public constant startTime = 1601793154;
    uint256 public constant rewardRate = 102777777777777;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored = 0;
    bool private open = true;
    uint256 private constant _gunit = 1e18;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event SetOpen(bool _open);

    function sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address token0, address token1)
    {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

    function pairFor(
        address factory,
        address token0,
        address token1
    ) internal pure returns (address pair) {
        pair = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex"ff",
                        factory,
                        keccak256(abi.encodePacked(token0, token1)),
                        hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f" // init code hash
                    )
                )
            )
        );
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, block.timestamp.add(10000));
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate)
            );
    }

    // 当前收益
    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(_gunit)
                .add(rewards[account]);
    }

    function stake(uint256 amount)
        public
        checkOpen
        checkStart
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot stake 0");
        uint256 amountOf = balanceOf(msg.sender).add(amount);
        require(
            amountOf <= stakeMax.mul(_gunit),
            "POK-POOL: Amount Can Not heigeht 10000"
        );
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        checkStart
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot withdraw 0");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function getReward()
        public
        checkStart
        updateReward(msg.sender)
        returns (uint256)
    {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
        }
        return reward;
    }

    modifier checkStart() {
        require(block.timestamp > startTime, "Not start");
        _;
    }

    modifier checkOpen() {
        require(open, "Pool is closed");
        _;
    }

    function isOpen() external view returns (bool) {
        return open;
    }

    function setOpen(bool _open) external onlyOwner {
        open = _open;
        emit SetOpen(_open);
    }
}
