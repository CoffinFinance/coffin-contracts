// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
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

interface ICollateralReserveV2 {
  function rebalance(
    address token0,
    address token1,
    uint256 _amount,
    uint256 _min_output_amount,
    bool nocheckcollateral,
    address routerAddress
  ) external;

  function rebalanceWithRouterPath(
    address token0,
    address token1,
    uint256 _amount,
    uint256 _min_output_amount,
    bool nocheckcollateral,
    address[] memory router_path,
    address routerAddress
  ) external;

  function createLiquidity(
    address token0,
    address token1,
    uint256 amtToken0,
    uint256 amtToken1,
    uint256 minToken0,
    uint256 minToken1,
    address routerAddrsss
  )
    external
    returns (
      uint256,
      uint256,
      uint256
    );

  function removeLiquidity(
    address token0,
    address token1,
    uint256 liquidity,
    uint256 minToken0,
    uint256 minToken1,
    address routerAddrsss
  )
    external
    returns (
      uint256,
      uint256,
      uint256
    );

  function yvDeposit(
    address _token0,
    address _token1,
    uint256 _amount
  ) external;

  function yvWithdraw(address _token, uint256 _amount) external;

  function stakeCoffin(uint256 _amount) external;

  function stakeBOO(uint256 _amount) external;

  function unstakeXBOO(uint256 _amount) external;

  function getCollateralBalance(address _token) external view returns (uint256);

  function getCollateralPrice(address _token) external view returns (uint256);

  function valueOf(address _token, uint256 _amount) external view returns (uint256 value_);

  function getValue(address _token, uint256 _amt) external view returns (uint256);

  function getCollateralValue(address _token) external view returns (uint256);

  function getActualCollateralValue() external view returns (uint256);

  function getTotalCollateralValue() external view returns (uint256);

  function addCollateral(address _token, ICollateralReserveV2Calc _token_oracle) external;

  function removeCollateral(address _token) external;
}

contract CollateralReserveV2Manager is Ownable {
  address public collateralReserveV2;
  address public manager;

  //wftm
  address private wftm = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
  //
  address private usdc = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
  address private dai = 0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E;
  address private mim = 0x82f0B8B456c1A451378467398982d4834b6829c1;
  address private weth = 0x74b23882a30290451A17c44f4F05243b6b58C76d;
  address private yvdai = 0x637eC617c86D24E421328e6CAEa1d92114892439;
  address private yvmim = 0x0A0b23D9786963DE69CB2447dC125c49929419d8;
  address private xboo = 0xa48d959AE2E88f1dAA7D5F611E01908106dE7598;
  address private boo = 0x841FAD6EAe12c286d1Fd18d1d525DFfA75C7EFFE;
  address private yvusdc = 0xEF0210eB96c7EB36AF8ed1c20306462764935607;
  address private nice = 0x7f620d7d0b3479b1655cEFB1B0Bc67fB0EF4E443;
  address private wmemo = 0xDDc0385169797937066bBd8EF409b5B3c0dFEB52;
  address private sspell = 0xbB29D2A58d880Af8AA5859e30470134dEAf84F2B;

  receive() external payable {
    IWETH(wftm).deposit{value: msg.value}();
    IERC20(wftm).transfer(collateralReserveV2, msg.value);
  }

  // router address. it's spooky router by default.
  address private spookyRouterAddress = 0xF491e7B69E4244ad4002BC14e878a34207E38c29;
  address private morpheusswapRouterAddress = 0x8aC868293D97761A1fED6d4A01E9FF17C5594Aa3;

  constructor(address _collateralReserveV2) {
    collateralReserveV2 = _collateralReserveV2;
  }

  /* ========== MODIFIER ========== */

  modifier onlyOwnerOrManager() {
    require(
      owner() == msg.sender || manager == msg.sender,
      'Only owner or manager can trigger this function'
    );
    _;
  }

  /* ========== VIEWS ================ */

  function balanceToken(address _token) public view returns (uint256) {
    return IERC20(_token).balanceOf(address(collateralReserveV2));
  }

  function setManager(address _manager) public onlyOwner {
    require(_manager != address(0), 'Invalid address');
    manager = _manager;
  }

  // function setBuybackManager(address _buyback_manager) public onlyOwner {
  //     require(_buyback_manager != address(0), "Invalid address");
  //     buyback_manager = _buyback_manager;
  // }

  function rebalanceFTM2BOO(uint256 _amount, uint256 _min) public onlyOwnerOrManager {
    rebalance(wftm, boo, _amount, _min, spookyRouterAddress);
  }

  function rebalanceBOO2FTM(uint256 _amount, uint256 _min) public onlyOwnerOrManager {
    rebalance(boo, wftm, _amount, _min, spookyRouterAddress);
  }

  function rebalanceFTM2MIM(uint256 _amount, uint256 _min) public onlyOwnerOrManager {
    rebalance(wftm, mim, _amount, _min, spookyRouterAddress);
  }

  function rebalanceMIM2FTM(uint256 _amount, uint256 _min) public onlyOwnerOrManager {
    rebalance(mim, wftm, _amount, _min, spookyRouterAddress);
  }

  function rebalanceFTM2DAI(uint256 _amount, uint256 _min) public onlyOwnerOrManager {
    rebalance(wftm, dai, _amount, _min, spookyRouterAddress);
  }

  function rebalanceDAI2FTM(uint256 _amount, uint256 _min) public onlyOwnerOrManager {
    rebalance(dai, wftm, _amount, _min, spookyRouterAddress);
  }

  function rebalanceUSDC2FTM(uint256 _amount, uint256 _min) public onlyOwnerOrManager {
    rebalance(usdc, wftm, _amount, _min, spookyRouterAddress);
  }

  function rebalanceFTM2USDC(uint256 _amount, uint256 _min) public onlyOwnerOrManager {
    rebalance(wftm, usdc, _amount, _min, spookyRouterAddress);
  }

  function rebalanceFTM2WETH(uint256 _amount, uint256 _min) public onlyOwnerOrManager {
    rebalance(wftm, weth, _amount, _min, spookyRouterAddress);
  }

  function rebalanceWETH2FTM(uint256 _amount, uint256 _min) public onlyOwnerOrManager {
    rebalance(weth, wftm, _amount, _min, spookyRouterAddress);
  }

  function rebalanceMIM2WMEMO(uint256 _amount, uint256 _min) public onlyOwnerOrManager {
    rebalance(mim, wmemo, _amount, _min, morpheusswapRouterAddress);
  }

  function rebalanceMIM2SSPELL(uint256 _amount, uint256 _min) public onlyOwnerOrManager {
    rebalance(mim, sspell, _amount, _min, morpheusswapRouterAddress);
  }

  function rebalanceMIM2NICE(uint256 _amount, uint256 _min) public onlyOwnerOrManager {
    rebalance(mim, nice, _amount, _min, morpheusswapRouterAddress);
  }

  function rebalanceWMEMO2MIM(uint256 _amount, uint256 _min) public onlyOwnerOrManager {
    rebalance(wmemo, mim, _amount, _min, morpheusswapRouterAddress);
  }

  function rebalanceSSPELL2MIM(uint256 _amount, uint256 _min) public onlyOwnerOrManager {
    rebalance(sspell, mim, _amount, _min, morpheusswapRouterAddress);
  }

  function rebalanceNICE2MIM(uint256 _amount, uint256 _min) public onlyOwnerOrManager {
    rebalance(nice, mim, _amount, _min, morpheusswapRouterAddress);
  }

  function stakeBOO(uint256 _amount) public onlyOwnerOrManager {
    ICollateralReserveV2(collateralReserveV2).stakeBOO(_amount);
  }

  function unstakeXBOO(uint256 _amount) public onlyOwnerOrManager {
    ICollateralReserveV2(collateralReserveV2).unstakeXBOO(_amount);
  }

  function rebalanceDAI2YVDAI(uint256 _amount) public onlyOwnerOrManager {
    ICollateralReserveV2(collateralReserveV2).yvDeposit(dai, yvdai, _amount);
  }

  function rebalanceYVDAI2DAI(uint256 _amount) public onlyOwnerOrManager {
    ICollateralReserveV2(collateralReserveV2).yvWithdraw(yvdai, _amount);
  }

  function rebalanceMIM2YVMIM(uint256 _amount) public onlyOwnerOrManager {
    ICollateralReserveV2(collateralReserveV2).yvDeposit(mim, yvmim, _amount);
  }

  function rebalanceYVMIM2MIM(uint256 _amount) public onlyOwnerOrManager {
    ICollateralReserveV2(collateralReserveV2).yvWithdraw(yvmim, _amount);
  }

  function rebalanceUSDC2YVUSDC(uint256 _amount) public onlyOwnerOrManager {
    ICollateralReserveV2(collateralReserveV2).yvDeposit(usdc, yvusdc, _amount);
  }

  function rebalanceYVUSDC2USDC(uint256 _amount) public onlyOwnerOrManager {
    ICollateralReserveV2(collateralReserveV2).yvWithdraw(yvusdc, _amount);
  }

  function rebalance(
    address token0,
    address token1,
    uint256 _amount,
    uint256 _min_output_amount,
    // bool nocheckcollateral,
    address routerAddress
  ) public onlyOwnerOrManager {
    return
      ICollateralReserveV2(collateralReserveV2).rebalance(
        token0,
        token1,
        _amount,
        _min_output_amount,
        false,
        routerAddress
      );
  }

  function rebalanceWithRouterPath(
    address token0,
    address token1,
    uint256 _amount,
    uint256 _min_output_amount,
    // bool nocheckcollateral,
    address[] memory router_path,
    address routerAddress
  ) public onlyOwnerOrManager {
    return
      ICollateralReserveV2(collateralReserveV2).rebalanceWithRouterPath(
        token0,
        token1,
        _amount,
        _min_output_amount,
        false,
        router_path,
        routerAddress
      );
  }

  function createLiquiditySpookySwap(
    address token0,
    address token1,
    uint256 amtToken0,
    uint256 amtToken1,
    uint256 minToken0,
    uint256 minToken1
  )
    external
    onlyOwnerOrManager
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    return
      createLiquidity(
        token0,
        token1,
        amtToken0,
        amtToken1,
        minToken0,
        minToken1,
        spookyRouterAddress
      );
  }

  function createLiquidityMorpheusSwap(
    address token0,
    address token1,
    uint256 amtToken0,
    uint256 amtToken1,
    uint256 minToken0,
    uint256 minToken1
  )
    external
    onlyOwnerOrManager
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    return
      createLiquidity(
        token0,
        token1,
        amtToken0,
        amtToken1,
        minToken0,
        minToken1,
        morpheusswapRouterAddress
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
    return
      ICollateralReserveV2(collateralReserveV2).createLiquidity(
        token0,
        token1,
        amtToken0,
        amtToken1,
        minToken0,
        minToken1,
        routerAddrsss
      );
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
    return
      ICollateralReserveV2(collateralReserveV2).removeLiquidity(
        token0,
        token1,
        liquidity,
        minToken0,
        minToken1,
        routerAddrsss
      );
  }

  function removeLiquidityMorpheusSwap(
    address token0,
    address token1,
    uint256 liquidity,
    uint256 minToken0,
    uint256 minToken1
  )
    external
    onlyOwnerOrManager
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    return
      removeLiquidity(
        token0,
        token1,
        liquidity,
        minToken0,
        minToken1,
        morpheusswapRouterAddress
      );
  }

  function removeLiquiditySpookySwap(
    address token0,
    address token1,
    uint256 liquidity,
    uint256 minToken0,
    uint256 minToken1
  )
    external
    onlyOwnerOrManager
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    return
      removeLiquidity(token0, token1, liquidity, minToken0, minToken1, spookyRouterAddress);
  }

  function addCollateral(address _token, ICollateralReserveV2Calc _token_oracle)
    public
    onlyOwnerOrManager
  {
    ICollateralReserveV2(collateralReserveV2).addCollateral(_token, _token_oracle);
  }

  function removeCollateral(address _token) public onlyOwnerOrManager {
    ICollateralReserveV2(collateralReserveV2).removeCollateral(_token);
  }

  function getCollateralBalance(address _token) external view returns (uint256) {
    return ICollateralReserveV2(collateralReserveV2).getCollateralBalance(_token);
  }

  function getCollateralPrice(address _token) external view returns (uint256) {
    return ICollateralReserveV2(collateralReserveV2).getCollateralPrice(_token);
  }

  function valueOf(address _token, uint256 _amount) external view returns (uint256 value_) {
    return ICollateralReserveV2(collateralReserveV2).valueOf(_token, _amount);
  }

  function getValue(address _token, uint256 _amt) external view returns (uint256) {
    return ICollateralReserveV2(collateralReserveV2).getValue(_token, _amt);
  }

  function getCollateralValue(address _token) external view returns (uint256) {
    return ICollateralReserveV2(collateralReserveV2).getCollateralValue(_token);
  }

  function getActualCollateralValue() external view returns (uint256) {
    return ICollateralReserveV2(collateralReserveV2).getActualCollateralValue();
  }

  function getTotalCollateralValue() external view returns (uint256) {
    return ICollateralReserveV2(collateralReserveV2).getTotalCollateralValue();
  }
}
