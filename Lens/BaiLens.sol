pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../BBep20.sol";
import "../BToken.sol";
import "../PriceOracle.sol";
import "../EIP20Interface.sol";
import "../Governance/GovernorAlpha.sol";
import "../Governance/XBID.sol";

interface ComptrollerLensInterface {
    function markets(address) external view returns (bool, uint);
    function oracle() external view returns (PriceOracle);
    function getAccountLiquidity(address) external view returns (uint, uint, uint);
    function getAssetsIn(address) external view returns (BToken[] memory);
    function claimBai(address) external;
    function venusAccrued(address) external view returns (uint);
}

contract BaiLens {
    struct BTokenMetadata {
        address bToken;
        uint exchangeRateCurrent;
        uint supplyRatePerBlock;
        uint borrowRatePerBlock;
        uint reserveFactorMantissa;
        uint totalBorrows;
        uint totalReserves;
        uint totalSupply;
        uint totalCash;
        bool isListed;
        uint collateralFactorMantissa;
        address underlyingAssetAddress;
        uint bTokenDecimals;
        uint underlyingDecimals;
    }

    function bTokenMetadata(BToken bToken) public returns (BTokenMetadata memory) {
        uint exchangeRateCurrent = bToken.exchangeRateCurrent();
        ComptrollerLensInterface comptroller = ComptrollerLensInterface(address(bToken.comptroller()));
        (bool isListed, uint collateralFactorMantissa) = comptroller.markets(address(bToken));
        address underlyingAssetAddress;
        uint underlyingDecimals;

        if (compareStrings(bToken.symbol(), "vBNB")) {
            underlyingAssetAddress = address(0);
            underlyingDecimals = 18;
        } else {
            BBep20 vBep20 = BBep20(address(bToken));
            underlyingAssetAddress = vBep20.underlying();
            underlyingDecimals = EIP20Interface(vBep20.underlying()).decimals();
        }

        return BTokenMetadata({
            bToken: address(bToken),
            exchangeRateCurrent: exchangeRateCurrent,
            supplyRatePerBlock: bToken.supplyRatePerBlock(),
            borrowRatePerBlock: bToken.borrowRatePerBlock(),
            reserveFactorMantissa: bToken.reserveFactorMantissa(),
            totalBorrows: bToken.totalBorrows(),
            totalReserves: bToken.totalReserves(),
            totalSupply: bToken.totalSupply(),
            totalCash: bToken.getCash(),
            isListed: isListed,
            collateralFactorMantissa: collateralFactorMantissa,
            underlyingAssetAddress: underlyingAssetAddress,
            bTokenDecimals: bToken.decimals(),
            underlyingDecimals: underlyingDecimals
        });
    }

    function bTokenMetadataAll(BToken[] calldata bTokens) external returns (BTokenMetadata[] memory) {
        uint bTokenCount = bTokens.length;
        BTokenMetadata[] memory res = new BTokenMetadata[](bTokenCount);
        for (uint i = 0; i < bTokenCount; i++) {
            res[i] = bTokenMetadata(bTokens[i]);
        }
        return res;
    }

    struct BTokenBalances {
        address bToken;
        uint balanceOf;
        uint borrowBalanceCurrent;
        uint balanceOfUnderlying;
        uint tokenBalance;
        uint tokenAllowance;
    }

    function bTokenBalances(BToken bToken, address payable account) public returns (BTokenBalances memory) {
        uint balanceOf = bToken.balanceOf(account);
        uint borrowBalanceCurrent = bToken.borrowBalanceCurrent(account);
        uint balanceOfUnderlying = bToken.balanceOfUnderlying(account);
        uint tokenBalance;
        uint tokenAllowance;

        if (compareStrings(bToken.symbol(), "vBNB")) {
            tokenBalance = account.balance;
            tokenAllowance = account.balance;
        } else {
            BBep20 vBep20 = BBep20(address(bToken));
            EIP20Interface underlying = EIP20Interface(vBep20.underlying());
            tokenBalance = underlying.balanceOf(account);
            tokenAllowance = underlying.allowance(account, address(bToken));
        }

        return BTokenBalances({
            bToken: address(bToken),
            balanceOf: balanceOf,
            borrowBalanceCurrent: borrowBalanceCurrent,
            balanceOfUnderlying: balanceOfUnderlying,
            tokenBalance: tokenBalance,
            tokenAllowance: tokenAllowance
        });
    }

    function bTokenBalancesAll(BToken[] calldata bTokens, address payable account) external returns (BTokenBalances[] memory) {
        uint bTokenCount = bTokens.length;
        BTokenBalances[] memory res = new BTokenBalances[](bTokenCount);
        for (uint i = 0; i < bTokenCount; i++) {
            res[i] = bTokenBalances(bTokens[i], account);
        }
        return res;
    }

    struct BTokenUnderlyingPrice {
        address bToken;
        uint underlyingPrice;
    }

    function bTokenUnderlyingPrice(BToken bToken) public view returns (BTokenUnderlyingPrice memory) {
        ComptrollerLensInterface comptroller = ComptrollerLensInterface(address(bToken.comptroller()));
        PriceOracle priceOracle = comptroller.oracle();

        return BTokenUnderlyingPrice({
            bToken: address(bToken),
            underlyingPrice: priceOracle.getUnderlyingPrice(bToken)
        });
    }

    function bTokenUnderlyingPriceAll(BToken[] calldata bTokens) external view returns (BTokenUnderlyingPrice[] memory) {
        uint bTokenCount = bTokens.length;
        BTokenUnderlyingPrice[] memory res = new BTokenUnderlyingPrice[](bTokenCount);
        for (uint i = 0; i < bTokenCount; i++) {
            res[i] = bTokenUnderlyingPrice(bTokens[i]);
        }
        return res;
    }

    struct AccountLimits {
        BToken[] markets;
        uint liquidity;
        uint shortfall;
    }

    function getAccountLimits(ComptrollerLensInterface comptroller, address account) public view returns (AccountLimits memory) {
        (uint errorCode, uint liquidity, uint shortfall) = comptroller.getAccountLiquidity(account);
        require(errorCode == 0, "account liquidity error");

        return AccountLimits({
            markets: comptroller.getAssetsIn(account),
            liquidity: liquidity,
            shortfall: shortfall
        });
    }

    struct GovReceipt {
        uint proposalId;
        bool hasVoted;
        bool support;
        uint96 votes;
    }

    function getGovReceipts(GovernorAlpha governor, address voter, uint[] memory proposalIds) public view returns (GovReceipt[] memory) {
        uint proposalCount = proposalIds.length;
        GovReceipt[] memory res = new GovReceipt[](proposalCount);
        for (uint i = 0; i < proposalCount; i++) {
            GovernorAlpha.Receipt memory receipt = governor.getReceipt(proposalIds[i], voter);
            res[i] = GovReceipt({
                proposalId: proposalIds[i],
                hasVoted: receipt.hasVoted,
                support: receipt.support,
                votes: receipt.votes
            });
        }
        return res;
    }

    struct GovProposal {
        uint proposalId;
        address proposer;
        uint eta;
        address[] targets;
        uint[] values;
        string[] signatures;
        bytes[] calldatas;
        uint startBlock;
        uint endBlock;
        uint forVotes;
        uint againstVotes;
        bool canceled;
        bool executed;
    }

    function setProposal(GovProposal memory res, GovernorAlpha governor, uint proposalId) internal view {
        (
            ,
            address proposer,
            uint eta,
            uint startBlock,
            uint endBlock,
            uint forVotes,
            uint againstVotes,
            bool canceled,
            bool executed
        ) = governor.proposals(proposalId);
        res.proposalId = proposalId;
        res.proposer = proposer;
        res.eta = eta;
        res.startBlock = startBlock;
        res.endBlock = endBlock;
        res.forVotes = forVotes;
        res.againstVotes = againstVotes;
        res.canceled = canceled;
        res.executed = executed;
    }

    function getGovProposals(GovernorAlpha governor, uint[] calldata proposalIds) external view returns (GovProposal[] memory) {
        GovProposal[] memory res = new GovProposal[](proposalIds.length);
        for (uint i = 0; i < proposalIds.length; i++) {
            (
                address[] memory targets,
                uint[] memory values,
                string[] memory signatures,
                bytes[] memory calldatas
            ) = governor.getActions(proposalIds[i]);
            res[i] = GovProposal({
                proposalId: 0,
                proposer: address(0),
                eta: 0,
                targets: targets,
                values: values,
                signatures: signatures,
                calldatas: calldatas,
                startBlock: 0,
                endBlock: 0,
                forVotes: 0,
                againstVotes: 0,
                canceled: false,
                executed: false
            });
            setProposal(res[i], governor, proposalIds[i]);
        }
        return res;
    }

    struct XBIDBalanceMetadata {
        uint balance;
        uint votes;
        address delegate;
    }

    function getXBIDBalanceMetadata(XBID xvs, address account) external view returns (XBIDBalanceMetadata memory) {
        return XBIDBalanceMetadata({
            balance: xvs.balanceOf(account),
            votes: uint256(xvs.getCurrentVotes(account)),
            delegate: xvs.delegates(account)
        });
    }

    struct XBIDBalanceMetadataExt {
        uint balance;
        uint votes;
        address delegate;
        uint allocated;
    }

    function getXBIDBalanceMetadataExt(XBID xvs, ComptrollerLensInterface comptroller, address account) external returns (XBIDBalanceMetadataExt memory) {
        uint balance = xvs.balanceOf(account);
        comptroller.claimBai(account);
        uint newBalance = xvs.balanceOf(account);
        uint accrued = comptroller.venusAccrued(account);
        uint total = add(accrued, newBalance, "sum xvs total");
        uint allocated = sub(total, balance, "sub allocated");

        return XBIDBalanceMetadataExt({
            balance: balance,
            votes: uint256(xvs.getCurrentVotes(account)),
            delegate: xvs.delegates(account),
            allocated: allocated
        });
    }

    struct BaiVotes {
        uint blockNumber;
        uint votes;
    }

    function getBaiVotes(XBID xvs, address account, uint32[] calldata blockNumbers) external view returns (BaiVotes[] memory) {
        BaiVotes[] memory res = new BaiVotes[](blockNumbers.length);
        for (uint i = 0; i < blockNumbers.length; i++) {
            res[i] = BaiVotes({
                blockNumber: uint256(blockNumbers[i]),
                votes: uint256(xvs.getPriorVotes(account, blockNumbers[i]))
            });
        }
        return res;
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function add(uint a, uint b, string memory errorMessage) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub(uint a, uint b, string memory errorMessage) internal pure returns (uint) {
        require(b <= a, errorMessage);
        uint c = a - b;
        return c;
    }
}
