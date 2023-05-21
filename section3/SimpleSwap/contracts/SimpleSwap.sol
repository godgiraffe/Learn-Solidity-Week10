// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ISimpleSwap } from "./interface/ISimpleSwap.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract SimpleSwap is ISimpleSwap, ERC20 {
    // Implement core logic here
    address public tokenA;
    address public tokenB;

    uint256 public reserveA;
    uint256 public reserveB;
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    constructor(address _tokenA, address _tokenB) ERC20("LP_TOKEN", "LP") {
        if (_isContract(_tokenA) == false) revert("SimpleSwap: TOKENA_IS_NOT_CONTRACT");
        if (_isContract(_tokenB) == false) revert("SimpleSwap: TOKENB_IS_NOT_CONTRACT");
        if (_tokenA == _tokenB) revert("SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS");

        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function getReserves() external view returns (uint256 _reserveA, uint256 _reserveB) {
        _reserveA = reserveA;
        _reserveB = reserveB;
    }

    function _getReserves() internal view returns (uint256 _reserveA, uint256 _reserveB) {
        _reserveA = reserveA;
        _reserveB = reserveB;
    }

    function getTokenA() external view returns (address tokenA) {
        tokenA = tokenA;
    }

    function getTokenB() external view returns (address tokenB) {
        tokenB = tokenB;
    }

    /// @notice Swap tokenIn for tokenOut with amountIn
    /// @param _tokenIn The address of the token to swap from
    /// @param _tokenOut The address of the token to swap to
    /// @param _amountIn The amount of tokenIn to swap
    /// @return amountOut The amount of tokenOut received
    function swap(address _tokenIn, address _tokenOut, uint256 _amountIn) external returns (uint256 amountOut) {
        if (_tokenIn != tokenA && _tokenIn != tokenB) revert("SimpleSwap: INVALID_TOKEN_IN");
        if (_tokenOut != tokenA && _tokenOut != tokenB ) revert("SimpleSwap: INVALID_TOKEN_OUT");
        if (_tokenIn == tokenA && _tokenOut == tokenA) revert("SimpleSwap: IDENTICAL_ADDRESS");
        if (_tokenIn == tokenB && _tokenOut == tokenB) revert("SimpleSwap: IDENTICAL_ADDRESS");
        if (_amountIn == 0) revert("SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        /* === [ 原本是這樣寫 ] ===
        // 取得 swap 前，池子的儲備狀況
        (uint256 reserveA, uint256 reserveB) = _getReserves();
        uint256 oldK = reserveA * reserveB;

        // 計算 swap 後，池子的儲備狀況，以及 swap 後，user 應該得到的 amountOut 數量
        uint256 reserveIn;
        uint256 reserveOut;
        uint256 amountOut;
        if (_tokenIn == tokenA) {
            reserveIn = reserveA + _amountIn;
            reserveOut = oldK / reserveIn;
            amountOut = reserveB - reserveOut;
        } else {
            reserveIn = reserveB + _amountIn;
            reserveOut = oldK / reserveIn;
            amountOut = reserveA - reserveOut;
        }
        */

        // 後來發現的作法
        uint256 beforSwapReserveIn = IERC20(_tokenIn).balanceOf(address(this));
        uint256 beforeSwapReserveOut = IERC20(_tokenOut).balanceOf(address(this));
        uint256 oldK = beforSwapReserveIn * beforeSwapReserveOut;
        uint256 amountOut = (beforeSwapReserveOut * _amountIn) / (beforSwapReserveIn + _amountIn);
        // bill 提供的作法...  待理解 = =
        // uint256 amountOut = beforeSwapReserveOut - ((beforSwapReserveIn * beforeSwapReserveOut -1) / (beforSwapReserveIn + _amountIn) + 1);
        // uint256 amountOut = reserveOut - ((reserveIn * reserveOut - 1) / (reserveIn + _amountIn) + 1)

        // 做 swap
        if ((beforSwapReserveIn + _amountIn) * (beforeSwapReserveOut + amountOut) < oldK) revert("new K < old K");
        IERC20(_tokenIn).transferFrom(msg.sender, address(this), _amountIn);
        IERC20(_tokenOut).transfer(msg.sender, amountOut);
        emit Swap(msg.sender, _tokenIn, _tokenOut, _amountIn, amountOut);

        // 更新池子儲備狀況
        uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(tokenB).balanceOf(address(this));
        _updateReserve(balanceA, balanceB);
    }

    /// @notice Add liquidity to the pool
    /// @param _amountAIn The amount of tokenA to add
    /// @param _amountBIn The amount of tokenB to add
    /// @return amountA The actually amount of tokenA added
    /// @return amountB The actually amount of tokenB added
    /// @return liquidity The amount of liquidity minted
    function addLiquidity(
        uint256 _amountAIn,
        uint256 _amountBIn
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // V2 無法添加單邊流動性，所以先檢查有沒有輸入 0 值
        if (_amountAIn == 0 || _amountBIn == 0) revert("SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        // 確認 user 的 tokenA & tokenB 夠不夠
        if (IERC20(tokenA).balanceOf(msg.sender) < _amountAIn) revert("INSUFFICIENT_TOKENA_AMOUNT");
        if (IERC20(tokenB).balanceOf(msg.sender) < _amountAIn) revert("INSUFFICIENT_TOKENB_AMOUNT");

        // token 夠的話，把 token 打進池子
        IERC20(tokenA).transferFrom(msg.sender, address(this), _amountAIn);
        IERC20(tokenB).transferFrom(msg.sender, address(this), _amountBIn);

        // 抓一下還沒存進來前的 雙 token 數量
        (uint256 reserveA, uint256 reserveB) = _getReserves();
        uint256 _liquidity;
        uint256 _totalSupply = IERC20(address(this)).totalSupply();

        if (_totalSupply == 0) {
            // 此測試不需考慮 MINIMUM_LIQUIDITY
            _liquidity = Math.sqrt(_amountAIn * _amountBIn); // - MINIMUM_LIQUIDITY;
            _mint(address(this), MINIMUM_LIQUIDITY); // init liquidity
        } else {
            _liquidity = _min((_amountAIn * _totalSupply) / reserveA, (_amountBIn * _totalSupply) / reserveB);
        }

        _mint(msg.sender, _liquidity);

        // 取得池子內，雙 token 的數量
        uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(tokenB).balanceOf(address(this));
        // 直接抓 balanceof 跟 ↓↓ 的方式不是差不多嗎？
        // 為何要選抓 balanceof 的方式呢？
        // reserveA += _amountAIn;
        // reserveB += _amountBIn;
        _updateReserve(balanceA, balanceB);

        // event AddLiquidity(address indexed sender, uint256 amountA, uint256 amountB, uint256 liquidity);
        emit AddLiquidity(msg.sender, _amountAIn, _amountBIn, _liquidity);
        return (reserveA, reserveB, _liquidity);
    }

    /// @notice Remove liquidity from the pool
    /// @param liquidity The amount of liquidity to remove
    /// @return amountA The amount of tokenA received
    /// @return amountB The amount of tokenB received
    function removeLiquidity(uint256 liquidity) external returns (uint256 amountA, uint256 amountB) {}

    function _updateReserve(uint256 _balanceA, uint256 _balanceB) internal {
        reserveA = _balanceA;
        reserveB = _balanceB;
    }

    ////////////////////////////////////////////////////////////////
    ///                                                          ///
    ///                        Utils                             ///
    ///                                                          ///
    ////////////////////////////////////////////////////////////////

    function _isContract(address _addr) private view returns (bool isContract) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    function _sortAddress(address _addr1, address _addr2) private pure returns (address, address) {
        if (uint160(_addr1) < uint160(_addr2)) return (_addr1, _addr2);
        return (_addr2, _addr1);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
