pragma solidity ^0.5.16;

import "./BToken.sol";
import "./PriceOracle.sol";
import "./ErrorReporter.sol";
import "./Exponential.sol";
import "./BAIControllerStorage.sol";
import "./BAIUnitroller.sol";
import "./BAI/BAI.sol";

interface ComptrollerLensInterface {
    function protocolPaused() external view returns (bool);
    function mintedBAIs(address account) external view returns (uint);
    function vaiMintRate() external view returns (uint);
    function venusBAIRate() external view returns (uint);
    function venusAccrued(address account) external view returns(uint);
    function getAssetsIn(address account) external view returns (BToken[] memory);
    function oracle() external view returns (PriceOracle);

    function distributeBAIMinterBai(address vaiMinter, bool distributeAll) external;
}

/**
 * @title Bai's BAI Comptroller Contract
 * @author Bai
 */
contract BAIController is BAIControllerStorage, BAIControllerErrorReporter, Exponential {

    /// @notice Emitted when Comptroller is changed
    event NewComptroller(ComptrollerInterface oldComptroller, ComptrollerInterface newComptroller);

    /**
     * @notice Event emitted when BAI is minted
     */
    event MintBAI(address minter, uint mintBAIAmount);

    /**
     * @notice Event emitted when BAI is repaid
     */
    event RepayBAI(address repayer, uint repayBAIAmount);

    /// @notice The initial Bai index for a market
    uint224 public constant venusInitialIndex = 1e36;

    /*** Main Actions ***/

    function mintBAI(uint mintBAIAmount) external returns (uint) {
        if(address(comptroller) != address(0)) {
            require(!ComptrollerLensInterface(address(comptroller)).protocolPaused(), "protocol is paused");

            address minter = msg.sender;

            // Keep the flywheel moving
            updateBaiBAIMintIndex();
            ComptrollerLensInterface(address(comptroller)).distributeBAIMinterBai(minter, false);

            uint oErr;
            MathError mErr;
            uint accountMintBAINew;
            uint accountMintableBAI;

            (oErr, accountMintableBAI) = getMintableBAI(minter);
            if (oErr != uint(Error.NO_ERROR)) {
                return uint(Error.REJECTION);
            }

            // check that user have sufficient mintableBAI balance
            if (mintBAIAmount > accountMintableBAI) {
                return fail(Error.REJECTION, FailureInfo.BAI_MINT_REJECTION);
            }

            (mErr, accountMintBAINew) = addUInt(ComptrollerLensInterface(address(comptroller)).mintedBAIs(minter), mintBAIAmount);
            require(mErr == MathError.NO_ERROR, "BAI_MINT_AMOUNT_CALCULATION_FAILED");
            uint error = comptroller.setMintedBAIOf(minter, accountMintBAINew);
            if (error != 0 ) {
                return error;
            }

            BAI(getBAIAddress()).mint(minter, mintBAIAmount);
            emit MintBAI(minter, mintBAIAmount);

            return uint(Error.NO_ERROR);
        }
    }

    /**
     * @notice Repay BAI
     */
    function repayBAI(uint repayBAIAmount) external returns (uint) {
        if(address(comptroller) != address(0)) {
            require(!ComptrollerLensInterface(address(comptroller)).protocolPaused(), "protocol is paused");

            address repayer = msg.sender;

            updateBaiBAIMintIndex();
            ComptrollerLensInterface(address(comptroller)).distributeBAIMinterBai(repayer, false);

            uint actualBurnAmount;

            uint vaiBalance = ComptrollerLensInterface(address(comptroller)).mintedBAIs(repayer);

            if(vaiBalance > repayBAIAmount) {
                actualBurnAmount = repayBAIAmount;
            } else {
                actualBurnAmount = vaiBalance;
            }

            uint error = comptroller.setMintedBAIOf(repayer, vaiBalance - actualBurnAmount);
            if (error != 0) {
                return error;
            }

            BAI(getBAIAddress()).burn(repayer, actualBurnAmount);
            emit RepayBAI(repayer, actualBurnAmount);

            return uint(Error.NO_ERROR);
        }
    }

    /**
     * @notice Initialize the BaiBAIState
     */
    function _initializeBaiBAIState(uint blockNumber) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_COMPTROLLER_OWNER_CHECK);
        }

        if (isBaiBAIInitialized == false) {
            isBaiBAIInitialized = true;
            uint vaiBlockNumber = blockNumber == 0 ? getBlockNumber() : blockNumber;
            venusBAIState = BaiBAIState({
                index: venusInitialIndex,
                block: safe32(vaiBlockNumber, "block number overflows")
            });
        }
    }

    /**
     * @notice Accrue XBID to by updating the BAI minter index
     */
    function updateBaiBAIMintIndex() public returns (uint) {
        uint vaiMinterSpeed = ComptrollerLensInterface(address(comptroller)).venusBAIRate();
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = sub_(blockNumber, uint(venusBAIState.block));
        if (deltaBlocks > 0 && vaiMinterSpeed > 0) {
            uint vaiAmount = BAI(getBAIAddress()).totalSupply();
            uint venusAccrued = mul_(deltaBlocks, vaiMinterSpeed);
            Double memory ratio = vaiAmount > 0 ? fraction(venusAccrued, vaiAmount) : Double({mantissa: 0});
            Double memory index = add_(Double({mantissa: venusBAIState.index}), ratio);
            venusBAIState = BaiBAIState({
                index: safe224(index.mantissa, "new index overflows"),
                block: safe32(blockNumber, "block number overflows")
            });
        } else if (deltaBlocks > 0) {
            venusBAIState.block = safe32(blockNumber, "block number overflows");
        }
    }

    /**
     * @notice Calculate XBID accrued by a BAI minter
     * @param vaiMinter The address of the BAI minter to distribute XBID to
     */
    function calcDistributeBAIMinterBai(address vaiMinter) public returns(uint, uint, uint, uint) {
        // Check caller is comptroller
        if (msg.sender != address(comptroller)) {
            return (fail(Error.UNAUTHORIZED, FailureInfo.SET_COMPTROLLER_OWNER_CHECK), 0, 0, 0);
        }

        Double memory vaiMintIndex = Double({mantissa: venusBAIState.index});
        Double memory vaiMinterIndex = Double({mantissa: venusBAIMinterIndex[vaiMinter]});
        venusBAIMinterIndex[vaiMinter] = vaiMintIndex.mantissa;

        if (vaiMinterIndex.mantissa == 0 && vaiMintIndex.mantissa > 0) {
            vaiMinterIndex.mantissa = venusInitialIndex;
        }

        Double memory deltaIndex = sub_(vaiMintIndex, vaiMinterIndex);
        uint vaiMinterAmount = ComptrollerLensInterface(address(comptroller)).mintedBAIs(vaiMinter);
        uint vaiMinterDelta = mul_(vaiMinterAmount, deltaIndex);
        uint vaiMinterAccrued = add_(ComptrollerLensInterface(address(comptroller)).venusAccrued(vaiMinter), vaiMinterDelta);
        return (uint(Error.NO_ERROR), vaiMinterAccrued, vaiMinterDelta, vaiMintIndex.mantissa);
    }

    /*** Admin Functions ***/

    /**
      * @notice Sets a new comptroller
      * @dev Admin function to set a new comptroller
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function _setComptroller(ComptrollerInterface comptroller_) public returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_COMPTROLLER_OWNER_CHECK);
        }

        ComptrollerInterface oldComptroller = comptroller;
        comptroller = comptroller_;
        emit NewComptroller(oldComptroller, comptroller_);

        return uint(Error.NO_ERROR);
    }

    function _become(BAIUnitroller unitroller) public {
        require(msg.sender == unitroller.admin(), "only unitroller admin can change brains");
        require(unitroller._acceptImplementation() == 0, "change not authorized");
    }

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account total supply balance.
     *  Note that `bTokenBalance` is the number of bTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountAmountLocalVars {
        uint totalSupplyAmount;
        uint sumSupply;
        uint sumBorrowPlusEffects;
        uint bTokenBalance;
        uint borrowBalance;
        uint exchangeRateMantissa;
        uint oraclePriceMantissa;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

    function getMintableBAI(address minter) public view returns (uint, uint) {
        PriceOracle oracle = ComptrollerLensInterface(address(comptroller)).oracle();
        BToken[] memory enteredMarkets = ComptrollerLensInterface(address(comptroller)).getAssetsIn(minter);

        AccountAmountLocalVars memory vars; // Holds all our calculation results

        uint oErr;
        MathError mErr;

        uint accountMintableBAI;
        uint i;

        /**
         * We use this formula to calculate mintable BAI amount.
         * totalSupplyAmount * BAIMintRate - (totalBorrowAmount + mintedBAIOf)
         */
        for (i = 0; i < enteredMarkets.length; i++) {
            (oErr, vars.bTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = enteredMarkets[i].getAccountSnapshot(minter);
            if (oErr != 0) { // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
                return (uint(Error.SNAPSHOT_ERROR), 0);
            }
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            // Get the normalized price of the asset
            vars.oraclePriceMantissa = oracle.getUnderlyingPrice(enteredMarkets[i]);
            if (vars.oraclePriceMantissa == 0) {
                return (uint(Error.PRICE_ERROR), 0);
            }
            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});

            (mErr, vars.tokensToDenom) = mulExp(vars.exchangeRate, vars.oraclePrice);
            if (mErr != MathError.NO_ERROR) {
                return (uint(Error.MATH_ERROR), 0);
            }

            // sumSupply += tokensToDenom * bTokenBalance
            (mErr, vars.sumSupply) = mulScalarTruncateAddUInt(vars.tokensToDenom, vars.bTokenBalance, vars.sumSupply);
            if (mErr != MathError.NO_ERROR) {
                return (uint(Error.MATH_ERROR), 0);
            }

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            (mErr, vars.sumBorrowPlusEffects) = mulScalarTruncateAddUInt(vars.oraclePrice, vars.borrowBalance, vars.sumBorrowPlusEffects);
            if (mErr != MathError.NO_ERROR) {
                return (uint(Error.MATH_ERROR), 0);
            }
        }

        (mErr, vars.sumBorrowPlusEffects) = addUInt(vars.sumBorrowPlusEffects, ComptrollerLensInterface(address(comptroller)).mintedBAIs(minter));
        if (mErr != MathError.NO_ERROR) {
            return (uint(Error.MATH_ERROR), 0);
        }

        (mErr, accountMintableBAI) = mulUInt(vars.sumSupply, ComptrollerLensInterface(address(comptroller)).vaiMintRate());
        require(mErr == MathError.NO_ERROR, "BAI_MINT_AMOUNT_CALCULATION_FAILED");

        (mErr, accountMintableBAI) = divUInt(accountMintableBAI, 10000);
        require(mErr == MathError.NO_ERROR, "BAI_MINT_AMOUNT_CALCULATION_FAILED");


        (mErr, accountMintableBAI) = subUInt(accountMintableBAI, vars.sumBorrowPlusEffects);
        if (mErr != MathError.NO_ERROR) {
            return (uint(Error.REJECTION), 0);
        }

        return (uint(Error.NO_ERROR), accountMintableBAI);
    }

    function getBlockNumber() public view returns (uint) {
        return block.number;
    }

    /**
     * @notice Return the address of the BAI token
     * @return The address of BAI
     */
    function getBAIAddress() public view returns (address) {
        return 0x4BD17003473389A42DAF6a0a729f6Fdb328BbBd7;
    }
}
