pragma solidity ^0.5.16;
import "./SafeMath.sol";
import "./IBEP20.sol";

contract BAIVaultAdminStorage {
    /**
    * @notice Administrator for this contract
    */
    address public admin;

    /**
    * @notice Pending administrator for this contract
    */
    address public pendingAdmin;

    /**
    * @notice Active brains of BAI Vault
    */
    address public vaiVaultImplementation;

    /**
    * @notice Pending brains of BAI Vault
    */
    address public pendingBAIVaultImplementation;
}

contract BAIVaultStorage is BAIVaultAdminStorage {
    /// @notice The XBID TOKEN!
    IBEP20 public xvs;

    /// @notice The BAI TOKEN!
    IBEP20 public vai;

    /// @notice Guard variable for re-entrancy checks
    bool internal _notEntered;

    /// @notice XBID balance of vault
    uint256 public xvsBalance;

    /// @notice Accumulated XBID per share
    uint256 public accXBIDPerShare;

    //// pending rewards awaiting anyone to update
    uint256 public pendingRewards;

    /// @notice Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    // Info of each user that stakes tokens.
    mapping(address => UserInfo) public userInfo;
}
