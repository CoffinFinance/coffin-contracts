// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

import './interfaces/IUniswapV2Router.sol';
import './ICollateralReserveV2Calc.sol';

interface IWETH {
  function deposit() external payable;

  function transfer(address to, uint256 value) external returns (bool);

  function transferFrom(
    address src,
    address dst,
    uint256 wad
  ) external returns (bool);

  function withdraw(uint256) external;

  function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2Factory {
  function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IBooMirrorWorld {
  function leave(uint256 _share) external;

  function enter(uint256 _amount) external;

  function balanceOf(address account) external view returns (uint256);

  function xBOOForBOO(uint256 _xBOOAmount) external view returns (uint256 booAmount_);
}

interface ICoffinTheOtherWorld {
  function stake(uint256 _amount) external;

  function xcoffin() external view returns (address);

  function COFFINForxCOFFIN(uint256 _coffinAmount)
    external
    view
    returns (uint256 xCOFFINAmount_);
}

interface IXCoffin {
  function burn(uint256 amount) external;

  function balanceOf(address account) external view returns (uint256);
}

interface IyvToken {
  function deposit(uint256 _amount) external;

  function deposit(uint256 _amount, address _recipient) external;

  function withdraw(uint256 _amount) external;

  function withdraw(uint256 _amount, address _recipient) external;

  function balanceOf(address account) external view returns (uint256);
}

interface IDollar {
  function pool_burn_from(address addr, uint256 amount) external;

  function pool_mint(address addr, uint256 amount) external;

  function burnFrom(address addr, uint256 amount) external;

  function totalSupply() external view returns (uint256);
}

contract CollateralReserveV2 is Ownable {
  // contract CollateralReserveV2 is Ownable {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  address public manager;
  address public buyback_manager;

  uint256 private constant LIMIT_SWAP_TIME = 10 minutes;

  // //
  address[] public collaterals;
  mapping(address => bool) public isCollateral;
  mapping(address => bool) public acceptDeposit;
  mapping(address => bool) public acceptWithdraw;
  mapping(address => bool) public isDepositor;
  mapping(address => address) public tokenSpender;
  // address[] public depositors;

  uint256 private constant COLLATERAL_RATIO_MAX = 1e6;

  // oracles
  mapping(address => address) public collateralCalc;
  //
  uint256 private constant PRICE_PRECISION = 1e6;

  //wftm
  address public wftm = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
  //
  address public usdc = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
  address public dai = 0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E;
  address public xboo = 0xa48d959AE2E88f1dAA7D5F611E01908106dE7598;
  address public boo = 0x841FAD6EAe12c286d1Fd18d1d525DFfA75C7EFFE;

  address public coffin;
  address public cousd;
  //
  address public gatev1;
  address public gatev2;
  //
  address public reserveV1;

  //
  address xcoffin = 0xc8a0a1b63F65C53F565ddDB7fbcfdd2eaBE868ED;

  address public coffintheotherworld = 0x5e082C23d1c70466c518306320e4927ea4A844B4;
  address private boomirrorworld = 0xa48d959AE2E88f1dAA7D5F611E01908106dE7598;

  receive() external payable {
    IWETH(wftm).deposit{value: msg.value}();
  }

  // router address. it's spooky router by default.
  address private spookyRouterAddress = 0xF491e7B69E4244ad4002BC14e878a34207E38c29;
  address private morpheusswapRouterAddress = 0x8aC868293D97761A1fED6d4A01E9FF17C5594Aa3;

  constructor() {
    // gateV1/PROD
    gatev1 = address(0x98e119990E3653486d84Ba46b66BbC4d82f7f604);
    // gateV1/TEST
    // gatev1 = address(0x5d77a7efDd038eb701eB44F2fb47FBEb4D4025B0);

    // reserveV1/PROD
    reserveV1 = address(0x61Befe6E5f20217960bD8659cd3113CC1ca67d2F);
    // reserveV1/TEST
    // reserveV1 = address(0xc0f00b8FB1e95336D2f831fAFB594d0E53331071);

    // coffin(prod
    coffin = address(0x593Ab53baFfaF1E821845cf7080428366F030a9c); // coffin
    // coffin(test
    // coffin = address(0x894c3A00a4b1FF104401DD8f116d9C3E97dd9684); // test coffin

    // cousd prod
    cousd = address(0x0DeF844ED26409C5C46dda124ec28fb064D90D27); // dollar
    // cousd test
    // cousd = address(0xA51a63261A7dfdc7eD1E480223C2f705b9CbEE6F); // test dollar

    // msg.sender by default
    setManager(msg.sender);
    setBuybackManager(msg.sender);
    setGateV2(msg.sender);
  }

  /* ========== MODIFIER ========== */

  modifier onlyGate() {
    require(
      gatev2 == msg.sender || gatev1 == msg.sender,
      'Only gate can trigger this function'
    );
    _;
  }

  modifier onlyOwnerOrManager() {
    require(
      owner() == msg.sender || manager == msg.sender,
      'Only owner or manager can trigger this function'
    );
    _;
  }

  modifier onlyBuybackManagerOrOwner() {
    require(
      owner() == msg.sender || buyback_manager == msg.sender,
      'Only owner or buyback_manager can trigger this function'
    );
    _;
  }
  modifier onlyBuybackManagerOrOwnerOrGate() {
    require(
      owner() == msg.sender || gatev2 == msg.sender || buyback_manager == msg.sender,
      'Only owner or buyback_manager or Gate can trigger this function'
    );
    _;
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  function transferWftmTO(address _receiver, uint256 _amount) public onlyGate {
    transferTo(wftm, _receiver, _amount);
  }

  function transferTo(
    address _token,
    address _receiver,
    uint256 _amount
  ) public onlyGate {
    require(_receiver != address(0), 'Invalid address');
    require(_amount > 0, 'Cannot transfer zero amount');
    IERC20(_token).safeTransfer(_receiver, _amount);
    emit Transfer(msg.sender, _token, _receiver, _amount);
  }

  function setReserveV1(address _reserveV1) public onlyOwner {
    reserveV1 = _reserveV1;
    emit ReserveChangeV1(_reserveV1);
  }

  function setGateV2(address _gate) public onlyOwner {
    require(_gate != address(0), 'Invalid address');
    gatev2 = _gate;
    // isDepositor[_gate] = true;
    emit GateChangedV2(_gate);
  }

  function setGateV1(address _gate) public onlyOwner {
    require(_gate != address(0), 'Invalid address');
    gatev1 = _gate;
    // isDepositor[_gate] = true;
    emit GateChangedV1(_gate);
  }

  function setManager(address _manager) public onlyOwner {
    require(_manager != address(0), 'Invalid address');
    manager = _manager;
  }

  function setBuybackManager(address _buyback_manager) public onlyOwner {
    require(_buyback_manager != address(0), 'Invalid address');
    buyback_manager = _buyback_manager;
  }

  function disableWithdrawToken(address _token) external onlyOwnerOrManager {
    acceptWithdraw[_token] = false;
    emit DisableWithdrawToken(_token);
  }

  function enableWithdrawToken(address _token) external onlyOwner {
    acceptWithdraw[_token] = true;
    emit EnableWithdrawToken(_token);
  }

  function disableDepositToken(address _token) external onlyOwnerOrManager {
    acceptDeposit[_token] = false;
    emit DisableDepositToken(_token);
  }

  function enableDepositToken(address _token) external onlyOwnerOrManager {
    acceptDeposit[_token] = true;
    emit EnableDepositToken(_token);
  }

  function addDepositor(address addr) external onlyOwnerOrManager {
    isDepositor[addr] = true;
    emit AddDepositor(addr);
  }

  function removeDepositor(address addr) external onlyOwnerOrManager {
    delete isDepositor[addr];
    emit RemoveDepositor(addr);
  }

  function addTokenSpender(address _token, address _spender) external onlyOwner {
    tokenSpender[_token] = _spender;
    emit AddTokenSpender(_token, _spender);
  }

  function removeSpender(address _token) external onlyOwnerOrManager {
    delete tokenSpender[_token];
    emit RemoveTokenSpender(_token);
  }

  // add a collatereal
  function addCollateral(address _token, ICollateralReserveV2Calc _token_oracle)
    public
    onlyOwnerOrManager
  {
    require(_token != address(0), 'invalid token');
    require(address(_token_oracle) != address(0), 'invalid token');

    isCollateral[_token] = true;
    // acceptDeposit[_token] = true;
    collateralCalc[_token] = address(_token_oracle);
    if (!listContains(collaterals, _token)) {
      collaterals.push(_token);
    }
    emit CollateralAdded(_token);
  }

  // Remove a collatereal
  function removeCollateral(address _token) public onlyOwnerOrManager {
    require(_token != address(0), 'invalid token');
    // Delete from the mapping
    delete collateralCalc[_token];
    delete isCollateral[_token];
    delete acceptDeposit[_token];
    delete acceptWithdraw[_token];

    // 'Delete' from the array by setting the address to 0x0
    for (uint256 i = 0; i < collaterals.length; i++) {
      if (collaterals[i] == _token) {
        // coffin_pools_array[i] = address(0);
        // This will leave a null in the array and keep the indices the same
        delete collaterals[i];
        break;
      }
    }
    emit CollateralRemoved(_token);
  }

  function stakeBOO(uint256 _amount) public onlyOwnerOrManager {
    require(boomirrorworld != address(0), 'boomirrorworld address error');
    require(_amount != 0, 'amount error');
    IERC20(boo).approve(address(boomirrorworld), 0);
    IERC20(boo).approve(address(boomirrorworld), _amount);
    IBooMirrorWorld(boomirrorworld).enter(_amount);
  }

  function unstakeXBOO(uint256 _amount) public onlyOwnerOrManager {
    require(boomirrorworld != address(0), 'boomirrorworld address error');
    require(_amount != 0, 'amount error');
    IERC20(xboo).approve(address(boomirrorworld), 0);
    IERC20(xboo).approve(address(boomirrorworld), _amount);
    IBooMirrorWorld(boomirrorworld).leave(_amount);
  }

  function yvDeposit(
    address _token0,
    address _token1,
    uint256 _amount
  ) public onlyOwnerOrManager {
    IERC20(_token0).approve(address(_token1), 0);
    IERC20(_token0).approve(address(_token1), _amount);
    IyvToken(address(_token1)).deposit(_amount);
  }

  function yvWithdraw(address _token, uint256 _amount) public onlyOwnerOrManager {
    IERC20(_token).approve(address(_token), 0);
    IERC20(_token).approve(address(_token), _amount);
    IyvToken(address(_token)).withdraw(_amount);
  }

  function stakeCoffin(uint256 _amount) public onlyBuybackManagerOrOwnerOrGate {
    require(coffin != address(0), 'coffin address error');
    require(coffintheotherworld != address(0), 'coffintheotherworld address error');
    require(_amount != 0, 'amount error');
    IERC20(coffin).approve(address(coffintheotherworld), 0);
    IERC20(coffin).approve(address(coffintheotherworld), _amount);
    ICoffinTheOtherWorld(coffintheotherworld).stake(_amount);
  }

  // burn xcoffin by coffin
  function burnXCoffinByCoffin(uint256 _coffin_ammount) public onlyBuybackManagerOrOwnerOrGate {
    require(coffin != address(0), 'coffin address error');
    require(coffintheotherworld != address(0), 'coffintheotherworld address error');
    require(_coffin_ammount != 0, 'amount error');
    uint256 xcoffinAmmount = ICoffinTheOtherWorld(coffintheotherworld).COFFINForxCOFFIN(
      _coffin_ammount
    );
    uint256 balance = IXCoffin(ICoffinTheOtherWorld(coffintheotherworld).xcoffin()).balanceOf(
      address(this)
    );
    if (xcoffinAmmount > balance) {
      xcoffinAmmount = balance;
    }
    IXCoffin(ICoffinTheOtherWorld(coffintheotherworld).xcoffin()).burn(xcoffinAmmount);
  }

  // burn xcoffin
  function burnXCoffin(uint256 _amount) public onlyBuybackManagerOrOwnerOrGate {
    require(coffintheotherworld != address(0), 'coffin address error');
    IXCoffin(ICoffinTheOtherWorld(coffintheotherworld).xcoffin()).burn(_amount);
  }

  function rebalance(
    address token0,
    address token1,
    uint256 _amount,
    uint256 _min_output_amount,
    bool nocheckcollateral,
    address routerAddress
  ) public onlyOwnerOrManager {
    if (!nocheckcollateral) {
      require(isCollateral[token0] == true, 'not support it as collateral.');
      require(isCollateral[token1] == true, 'not collateral token');
    }
    IERC20(token0).approve(address(routerAddress), 0);
    IERC20(token0).approve(address(routerAddress), _amount);

    address[] memory router_path = new address[](2);
    router_path[0] = token0;
    router_path[1] = token1;

    uint256[] memory _received_amounts = IUniswapV2Router(routerAddress)
      .swapExactTokensForTokens(
        _amount,
        _min_output_amount,
        router_path,
        address(this),
        block.timestamp + LIMIT_SWAP_TIME
      );

    require(
      _received_amounts[_received_amounts.length - 1] >= _min_output_amount,
      'Slippage limit reached'
    );

    emit Rebalance(
      token0,
      token1,
      _amount,
      _min_output_amount,
      _received_amounts[_received_amounts.length - 1]
    );
  }

  function rebalanceWithRouterPath(
    address token0,
    address token1,
    uint256 _amount,
    uint256 _min_output_amount,
    bool nocheckcollateral,
    address[] memory router_path,
    address routerAddress
  ) public onlyOwnerOrManager {
    if (!nocheckcollateral) {
      require(isCollateral[token0] == true, 'not support it as collateral.');
      require(isCollateral[token1] == true, 'not collateral token');
    }
    IERC20(token0).approve(address(routerAddress), 0);
    IERC20(token0).approve(address(routerAddress), _amount);

    // address[] memory router_path = new address[](2);
    // router_path[0] = token0;
    // router_path[1] = token1;

    uint256[] memory _received_amounts = IUniswapV2Router(routerAddress)
      .swapExactTokensForTokens(
        _amount,
        _min_output_amount,
        router_path,
        address(this),
        block.timestamp + LIMIT_SWAP_TIME
      );

    require(
      _received_amounts[_received_amounts.length - 1] >= _min_output_amount,
      'Slippage limit reached'
    );

    emit Rebalance(
      token0,
      token1,
      _amount,
      _min_output_amount,
      _received_amounts[_received_amounts.length - 1]
    );
  }

  function createLiquidity(
    address token0,
    address token1,
    uint256 amtToken0,
    uint256 amtToken1,
    uint256 minToken0,
    uint256 minToken1,
    address routerAddrsss
  )
    public
    onlyOwnerOrManager
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    require(amtToken0 != 0 && amtToken1 != 0, "amounts can't be 0");

    IERC20(token0).approve(address(routerAddrsss), 0);
    IERC20(token0).approve(address(routerAddrsss), amtToken0);

    IERC20(token1).approve(address(routerAddrsss), 0);
    IERC20(token1).approve(address(routerAddrsss), amtToken1);

    uint256 resultAmtToken0;
    uint256 resultAmtToken1;
    uint256 liquidity;

    (resultAmtToken0, resultAmtToken1, liquidity) = IUniswapV2Router(routerAddrsss)
      .addLiquidity(
        token0,
        token1,
        amtToken0,
        amtToken1,
        minToken0,
        minToken1,
        address(this),
        block.timestamp + LIMIT_SWAP_TIME
      );
    return (resultAmtToken0, resultAmtToken1, liquidity);
  }

  function removeLiquidity(
    address token0,
    address token1,
    uint256 liquidity,
    uint256 minToken0,
    uint256 minToken1,
    address routerAddrsss
  )
    public
    onlyOwnerOrManager
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    require(minToken0 != 0 && minToken1 != 0, " can't be 0");

    address pair = IUniswapV2Factory(IUniswapV2Router(routerAddrsss).factory()).getPair(
      token0,
      token1
    );

    IERC20(pair).approve(address(routerAddrsss), 0);
    IERC20(pair).approve(address(routerAddrsss), liquidity);

    uint256 resultAmtToken0;
    uint256 resultAmtToken1;

    (resultAmtToken0, resultAmtToken1) = IUniswapV2Router(routerAddrsss).removeLiquidity(
      token0,
      token1,
      liquidity,
      minToken0,
      minToken1,
      address(this),
      block.timestamp + LIMIT_SWAP_TIME
    );
    emit CreateLiquidy(token0, token1, liquidity);
    return (resultAmtToken0, resultAmtToken1, liquidity);
  }

  /* ========== INTERNAL FUNCTIONS ========== */
  /**
        @notice checks array to ensure against duplicate
        @param _list address[]
        @param _token address
        @return bool
     */
  function listContains(address[] storage _list, address _token) internal view returns (bool) {
    for (uint256 i = 0; i < _list.length; i++) {
      if (_list[i] == _token) {
        return true;
      }
    }
    return false;
  }

  /* ========== PUBLIC FUNCTIONS ========== */

  function deposit(
    uint256 _amount,
    address _token,
    uint256 _out
  ) external {
    require(isCollateral[_token], 'Not accepted.');
    require(acceptDeposit[_token], 'Not accepted to deposit for now ');
    require(msg.sender == gatev2 || isDepositor[msg.sender], 'Not approved...');
    IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    IDollar(cousd).pool_mint(msg.sender, _out);
    emit Deposit(_token, _amount, _out);
  }

  function withdraw(uint256 _token_amount, address _token) external {
    require(isCollateral[_token], 'Not accepted..');
    require(acceptWithdraw[_token], 'Not accepted to withdraw for now ');
    require(msg.sender == gatev2 || tokenSpender[_token] == msg.sender, 'Not approved....');
    uint256 balance = IERC20(_token).balanceOf(address(this));
    require(balance >= _token_amount, 'no enough balance...');
    IERC20(_token).safeTransfer(msg.sender, _token_amount);
    emit Withdrawal(_token, _token_amount);
  }

  function excessReserves() public view returns (uint256) {
    // It doesn't care about unclaimed collaterals!!
    return getTotalCollateralValue().sub(IERC20(cousd).totalSupply());
  }

  // including unclaimed collaterals
  function getTotalCollateralValue() public view returns (uint256) {
    uint256 val = 0;
    for (uint256 i = 0; i < collaterals.length; i++) {
      if (
        address(collaterals[i]) != address(0) && collateralCalc[collaterals[i]] != address(0)
      ) {
        val += getCollateralValue(collaterals[i]);
      }
    }
    // if (val > v1Debt()) {
    //   val = val.sub(v1Debt());
    // }
    return val;
  }

  function dollarSupply() public view returns (uint256) {
    return IERC20(cousd).totalSupply();
  }

  //   function getActualCollateralRatio() public view returns (uint256 acr) {
  //     uint256 _collateral_value = getTotalCollateralValue();
  //     uint256 total_supply_dollar = dollarSupply();

  //     if (total_supply_dollar == 0) {
  //       return COLLATERAL_RATIO_MAX;
  //     }
  //     if (_collateral_value == 0) {
  //       return 0;
  //     }
  //     //  6 decimal
  //     acr = _collateral_value.mul(1e6).div(total_supply_dollar);
  //   }

  //   function getEffectiveCollateralRatio() public view returns (uint256 ecr) {
  //     ecr = getActualCollateralRatio();
  //     if (ecr > COLLATERAL_RATIO_MAX) {
  //       ecr = COLLATERAL_RATIO_MAX;
  //     }
  //     return ecr;
  //   }

  //   function getTotalCollateralRatio() public view returns (uint256 tcr) {
  //     uint256 tcv = getTotalCollateralValue();
  //     uint256 total_supply_dollar = dollarSupply();
  //     if (total_supply_dollar == 0) {
  //       return COLLATERAL_RATIO_MAX;
  //     }
  //     if (tcv == 0) {
  //       return 0;
  //     }

  //     tcr = tcv.mul(1e6).div(total_supply_dollar);
  //   }

  // 18 decimals
  function getCollateralValue(address _token) public view returns (uint256) {
    require(address(collateralCalc[_token]) != address(0), 'err0');
    return getCollateralBalance(_token).mul(getCollateralPrice(_token)).div(1e6);
  }

  // 18 decimals
  function getValue(address _token, uint256 _amt) public view returns (uint256) {
    require(address(collateralCalc[_token]) != address(0), 'err0');
    return _amt.mul(getCollateralPrice(_token)).div(1e6);
  }

  // 18 decimals
  function valueOf(address _token, uint256 _amount) public view returns (uint256 value_) {
    value_ = 0;
    try ICollateralReserveV2Calc(collateralCalc[_token]).valuation(_amount) returns (
      uint256 v
    ) {
      value_ = v;
    } catch Error(
      string memory /*reason*/
    ) {
      value_ = 0;
    }
  }

  // // 6 decimals
  function getCollateralPrice(address _token) public view returns (uint256) {
    require(address(collateralCalc[_token]) != address(0), 'err0');
    try ICollateralReserveV2Calc(collateralCalc[_token]).getPrice() returns (
      uint256 price,
      uint8 d
    ) {
      return price.mul(PRICE_PRECISION).div(10**d);
    } catch Error(
      string memory /*reason*/
    ) {
      return 0;
    }
  }

  function getCollateralBalance(address _token) public view returns (uint256) {
    require(address(_token) != address(0), 'err1');
    try ERC20(_token).decimals() returns (uint8 d) {
      uint256 missing_decimals = 18 - uint256(d);
      try IERC20(_token).balanceOf(address(this)) returns (uint256 balanceV2) {
        uint256 balanceV1 = 0;
        if (reserveV1 != address(0)) {
          balanceV1 = IERC20(_token).balanceOf(address(reserveV1));
        }
        return (balanceV2.add(balanceV1)).mul(10**missing_decimals);
      } catch Error(
        string memory /*reason*/
      ) {
        return 0;
      }
    } catch Error(
      string memory /*reason*/
    ) {
      return 0;
    }
  }

  /* ========== EVENTS  ========== */
  event GateChangedV1(address indexed _gate);
  event GateChangedV2(address indexed _gate);
  event ReserveChangeV1(address indexed _reserve);

  event Transfer(address se, address indexed token, address indexed receiver, uint256 amount);
  event Rebalance(
    address _from_address,
    address _to_address,
    uint256 _amount,
    uint256 _min_output_amount,
    uint256 _received_amount
  );

  event CollateralRemoved(address _token);
  event CollateralAdded(address _token);

  event CreateLiquidy(address token0, address token1, uint256 liquidity);
  event ReservesUpdated(uint256 indexed totalReserves);
  event RemoveLiquidy(address token0, address token1, uint256 liquidity);
  event Deposit(address indexed token, uint256 amount, uint256 out);
  event Withdrawal(address indexed token, uint256 amount);

  event AddDepositor(address addr);
  event RemoveDepositor(address addr);
  event AddTokenSpender(address token, address spender);
  event RemoveTokenSpender(address addr);

  event DisableDepositToken(address addr);
  event EnableDepositToken(address addr);
  event DisableWithdrawToken(address addr);
  event EnableWithdrawToken(address addr);
}
