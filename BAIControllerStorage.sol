pragma solidity ^0.5.16;

import "./ComptrollerInterface.sol";

contract BAIUnitrollerAdminStorage {
    /**
    * @notice Administrator for this contract
    */
    address public admin;

    /**
    * @notice Pending administrator for this contract
    */
    address public pendingAdmin;

    /**
    * @notice Active brains of Unitroller
    */
    address public vaiControllerImplementation;

    /**
    * @notice Pending brains of Unitroller
    */
    address public pendingBAIControllerImplementation;
}

contract BAIControllerStorage is BAIUnitrollerAdminStorage {
    ComptrollerInterface public comptroller;

    struct BaiBAIState {
        /// @notice The last updated venusBAIMintIndex
        uint224 index;

        /// @notice The block number the index was last updated at
        uint32 block;
    }

    /// @notice The Bai BAI state
    BaiBAIState public venusBAIState;

    /// @notice The Bai BAI state initialized
    bool public isBaiBAIInitialized;

    /// @notice The Bai BAI minter index as of the last time they accrued XBID
    mapping(address => uint) public venusBAIMinterIndex;
}
