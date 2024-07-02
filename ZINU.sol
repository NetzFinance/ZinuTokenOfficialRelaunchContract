//SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./DividendWrappedNative.sol";

/*
███████ ██ ███    ██ ██    ██ 
   ███  ██ ████   ██ ██    ██ 
  ███   ██ ██ ██  ██ ██    ██ 
 ███    ██ ██  ██ ██ ██    ██ 
███████ ██ ██   ████  ██████  
                                  
                                  
Linktree:
https://linktr.ee/ZinuToken

X:
https://x.com/zinutoken

Discord:
https://discord.gg/zinu

Telegram Announcements:
https://t.me/ZINU_Announcements

Website:
https://wearezinu.com/

OpenSea ZMSS Collection
https://opensea.io/collection/zombiemobsecretsociety
*/

contract ZINU is IZRC20, Ownable, Zodiac, FeeReceiver, Pausable {
    using SafeMath for uint256;

    struct Airdrop {
        address user;
        uint256 amount;
    }

    string public _name = "ZINU";
    string public _symbol = "ZINU";
    uint8 constant _decimals = 9;

    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;

    uint256 _totalSupply = 20000 * 10**5 * (10**_decimals);
    uint256 public _maxTxAmount = 20000 * 10**5 * (10**_decimals);
    uint256 public _walletMax = 20000 * 10**5 * (10**_decimals);

    bool public restrictWhales = true;

    mapping(address => uint256) _balances;
    mapping(address => mapping(address => uint256)) _allowances;

    mapping(address => bool) public isFeeExempt;
    mapping(address => bool) public isTxLimitExempt;
    mapping(address => bool) public isDividendExempt;

    uint256 public liquidityFee = 1;
    uint256 public marketingFee = 1;
    uint256 public rewardsFee = 1;
    uint256 public extraFeeOnSell = 0;

    uint256 public totalFee = 0;
    uint256 public totalFeeIfSelling = 0;

    address public marketingWallet = 0x527D18945288aed70AE8D4772Ec2D43D9fE08047;
    address public pair;

    uint256 public launchedAt;

    DividendWrappedNativeDistributor public dividendDistributor;

    uint256 distributorGas = 300000;

    bool inSwapAndLiquify;

    bool public swapAndLiquifyEnabled = true;
    bool public swapAndLiquifyByLimitOnly = false;

    uint256 public swapThreshold = 10 * 10**5 * (10**_decimals);

    string public _contractURI;

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    bool inAirdrop;
    mapping(uint256 => bool) public isBatchAirdropped;

    constructor(address _owner) Ownable(msg.sender) {
        feeSetterContract.setContractCreator(address(this));

        pair = INETZFactory(router.factory()).createPair(
            router.WETH(),
            address(this)
        );

        _allowances[address(this)][address(router)] = type(uint256).max;

        dividendDistributor = new DividendWrappedNativeDistributor();

        exemptFromAllLimits(_owner);

        isFeeExempt[address(this)] = true;

        isTxLimitExempt[pair] = true;

        isDividendExempt[pair] = true;
        isDividendExempt[address(this)] = true;
        isDividendExempt[DEAD] = true;
        isDividendExempt[ZERO] = true;

        totalFee = liquidityFee.add(marketingFee).add(rewardsFee);
        totalFeeIfSelling = totalFee.add(extraFeeOnSell);

        _balances[_owner] = _totalSupply;
        emit Transfer(address(0), _owner, _totalSupply);
        transferOwnership(_owner);
    }

    receive() external payable {}

    //========== TOKEN FUNCTIONS ==========\\
    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    function name() external view override returns (string memory) {
        return _name;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function decimals() external pure override returns (uint8) {
        return _decimals;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function getOwner() external view override returns (address) {
        return owner();
    }

    function getCirculatingSupply() public view returns (uint256) {
        return _totalSupply.sub(balanceOf(DEAD)).sub(balanceOf(ZERO));
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function allowance(address holder, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowances[holder][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, type(uint256).max);
    }

    //========== LAUNCH FUNCTIONS ==========\\
    function releaseTheHoarde() external onlyOwner {
        require(!launched(), "ZINU is launched");
        launch();
    }

    function pauseTransfers() external onlyOwner {
        _pause();
    }

    function unpauseTransfers() external onlyOwner {
        _unpause();
    }

    function setContractURI(string memory _newuri) external onlyOwner {
        _contractURI = _newuri;
    }

    //========== LIMIT FUNCTIONS ==========\\
    function changeTxLimit(uint256 newLimit) external onlyOwner {
        _maxTxAmount = newLimit;
    }

    function changeWalletLimit(uint256 newLimit) external onlyOwner {
        _walletMax = newLimit;
    }

    function changeRestrictWhales(bool newValue) external onlyOwner {
        restrictWhales = newValue;
    }

    function changeIsFeeExempt(address holder, bool exempt) public onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function changeIsTxLimitExempt(address holder, bool exempt)
        public
        onlyOwner
    {
        isTxLimitExempt[holder] = exempt;
    }

    function changeIsDividendExempt(address holder, bool exempt)
        public
        onlyOwner
    {
        require(holder != address(this) && holder != pair);
        isDividendExempt[holder] = exempt;

        if (exempt) {
            dividendDistributor.setShare(holder, 0);
        } else {
            dividendDistributor.setShare(holder, _balances[holder]);
        }
    }

    function exemptFromAllLimits(address account) public onlyOwner {
        changeIsDividendExempt(account, true);
        changeIsTxLimitExempt(account, true);
        changeIsFeeExempt(account, true);
    }

    //========== TAX FUNCTIONS ==========\\
    function changeFees(
        uint256 newLiqFee,
        uint256 newRewardFee,
        uint256 newMarketingFee,
        uint256 newExtraSellFee
    ) external onlyOwner {
        liquidityFee = newLiqFee;
        rewardsFee = newRewardFee;
        marketingFee = newMarketingFee;
        extraFeeOnSell = newExtraSellFee;

        totalFee = liquidityFee.add(marketingFee).add(rewardsFee);
        totalFeeIfSelling = totalFee.add(extraFeeOnSell);
    }

    function changeFeeReceiver(address _newMarketingWallet) external onlyOwner {
        marketingWallet = _newMarketingWallet;
    }

    //========== DISTRIBUTOR FUNCTIONS ==========\\
    function changeSwapBackSettings(
        bool enableSwapBack,
        uint256 newSwapBackLimit,
        bool swapByLimitOnly
    ) external onlyOwner {
        swapAndLiquifyEnabled = enableSwapBack;
        swapThreshold = newSwapBackLimit;
        swapAndLiquifyByLimitOnly = swapByLimitOnly;
    }

    function changeDistributionCriteria(
        uint256 newinPeriod,
        uint256 newMinDistribution
    ) external onlyOwner {
        dividendDistributor.setDistributionCriteria(
            newinPeriod,
            newMinDistribution
        );
    }

    function changeDistributorSettings(uint256 gas) external onlyOwner {
        require(gas < 300000);
        distributorGas = gas;
    }

    //========== BUY FUNCTIONS ==========\\
    function getReserves() public view returns (uint112, uint112) {
        (uint112 reserve0, uint112 reserve1, ) = INETZPair(pair).getReserves();
        return (reserve0, reserve1);
    }

    function buyTokens() public payable whenNotPaused {
        require(msg.value > 0, "Must send more netz");

        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(this);

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: msg.value
        }(0, path, msg.sender, block.timestamp);
    }

    //========== HELPER FUNCTIONS ==========\\
    function airdropTokensPublic(
        address[] memory _holders,
        uint256[] memory amounts
    ) public {
        require(_holders.length == amounts.length, "invalid lengths");
        for (uint256 i = 0; i < _holders.length; i++) {
            _transferFrom(msg.sender, _holders[i], amounts[i]);
        }
    }

    //========== TRANSFER FUNCTIONS ==========\\
    function airdropTokens(address[] memory _holders, uint256[] memory amounts)
        public
        onlyOwner
    {
        require(_holders.length == amounts.length, "invalid lengths");
        for (uint256 i = 0; i < _holders.length; i++) {
            _airdropTransferFrom(msg.sender, _holders[i], amounts[i]);
        }
    }

    function airdropMigratedTokensViaStruct(
        Airdrop[] memory _airdrop,
        uint256 _batch
    ) public onlyOwner {
        inAirdrop = true;
        require(!isBatchAirdropped[_batch], "all ready airdropped this batch");
        for (uint256 i = 0; i < _airdrop.length; i++) {
            _airdropTransferFrom(
                msg.sender,
                _airdrop[i].user,
                _airdrop[i].amount
            );
        }
        isBatchAirdropped[_batch] = true;
        inAirdrop = false;
        emit MigrationAirdrop(_batch);
    }

    function transfer(address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender]
                .sub(amount, "Insufficient Allowance");
        }
        return _transferFrom(sender, recipient, amount);
    }

    //========== INTERNAL FUNCTIONS ==========\\
    function _airdropTransferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal whenNotPaused returns (bool) {
        require(inAirdrop, "Token must be launched");
        _balances[sender] = _balances[sender].sub(
            amount,
            "Insufficient Balance"
        );
        _balances[recipient] = _balances[recipient].add(amount);

        if (!isDividendExempt[sender]) {
            dividendDistributor.setShare(sender, _balances[sender]);
        }

        if (!isDividendExempt[recipient]) {
            dividendDistributor.setShare(recipient, _balances[recipient]);
        }
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal whenNotPaused returns (bool) {
        require(
            (sender == owner() && recipient == pair) || launched(),
            "Token must be launched"
        );

        if (inSwapAndLiquify) {
            return _basicTransfer(sender, recipient, amount);
        }

        require(
            amount <= _maxTxAmount || isTxLimitExempt[sender],
            "TX Limit Exceeded"
        );

        if (
            msg.sender != pair &&
            sender != pair &&
            !inSwapAndLiquify &&
            swapAndLiquifyEnabled &&
            _balances[address(this)] >= swapThreshold
        ) {
            swapBack();
        }

        _balances[sender] = _balances[sender].sub(
            amount,
            "Insufficient Balance"
        );

        if (!isTxLimitExempt[recipient] && restrictWhales) {
            require(_balances[recipient].add(amount) <= _walletMax);
        }

        uint256 finalAmount = isFeeExempt[sender] ||
            isFeeExempt[recipient] ||
            (recipient != pair && sender != pair)
            ? amount
            : takeFee(sender, recipient, amount);

        _balances[recipient] = _balances[recipient].add(finalAmount);

        if (!isDividendExempt[sender]) {
            try
                dividendDistributor.setShare(sender, _balances[sender])
            {} catch {}
        }

        if (!isDividendExempt[recipient]) {
            try
                dividendDistributor.setShare(recipient, _balances[recipient])
            {} catch {}
        }

        try dividendDistributor.process(distributorGas) {} catch {}

        emit Transfer(sender, recipient, finalAmount);
        return true;
    }

    function _basicTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal whenNotPaused returns (bool) {
        _balances[sender] = _balances[sender].sub(
            amount,
            "Insufficient Balance"
        );
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function takeFee(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (uint256) {
        uint256 feeApplicable = pair == recipient
            ? totalFeeIfSelling
            : totalFee;
        uint256 feeAmount = amount.mul(feeApplicable).div(100);

        _balances[address(this)] = _balances[address(this)].add(feeAmount);
        emit Transfer(sender, address(this), feeAmount);
        return amount.sub(feeAmount);
    }

    function swapBack() internal lockTheSwap {
        uint256 tokensToLiquify = _balances[address(this)];
        uint256 amountToLiquify = tokensToLiquify
            .mul(liquidityFee)
            .div(totalFee)
            .div(2);
        uint256 amountToSwap = tokensToLiquify.sub(amountToLiquify);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountNETZ = address(this).balance;

        uint256 totalNETZFee = totalFee.sub(liquidityFee.div(2));

        uint256 amountNETZLiquidity = amountNETZ
            .mul(liquidityFee)
            .div(totalNETZFee)
            .div(2);
        uint256 amountNETZReflection = amountNETZ.mul(rewardsFee).div(
            totalNETZFee
        );
        uint256 amountNETZMarketing = amountNETZ.sub(amountNETZLiquidity).sub(
            amountNETZReflection
        );

        try
            dividendDistributor.deposit{value: amountNETZReflection}()
        {} catch {}

        (bool tmpSuccess, ) = payable(marketingWallet).call{
            value: amountNETZMarketing,
            gas: 30000
        }("");

        tmpSuccess = false;

        if (amountToLiquify > 0) {
            router.addLiquidityETH{value: amountNETZLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                DEAD,
                block.timestamp
            );
            emit AutoLiquify(amountNETZLiquidity, amountToLiquify);
        }
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function launch() internal {
        launchedAt = block.number;
    }

    //========== EVENTS ==========\\
    event AutoLiquify(uint256 amountNETZ, uint256 amountBOG);
    event MigrationAirdrop(uint256 indexed batch);
}
