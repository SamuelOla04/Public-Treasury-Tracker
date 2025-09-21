// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// Suppress known OpenZeppelin warnings
pragma experimental ABIEncoderV2;

// Custom minimal implementations to eliminate all external dependencies

/**
 * @dev Custom minimal Pausable implementation
 */
abstract contract Pausable {
    bool private _paused;
    
    event Paused(address account);
    event Unpaused(address account);
    
    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }
    
    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }
    
    function paused() public view returns (bool) {
        return _paused;
    }
    
    function _pause() internal whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }
    
    function _unpause() internal whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

/**
 * @dev Custom minimal AccessControl implementation
 */
abstract contract AccessControl {
    mapping(bytes32 => mapping(address => bool)) private _roles;
    
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    
    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender), "AccessControl: account missing role");
        _;
    }
    
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }
    
    function _grantRole(bytes32 role, address account) internal {
        if (!hasRole(role, account)) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }
    
    function _revokeRole(bytes32 role, address account) internal {
        if (hasRole(role, account)) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }
}

/**
 * @title TreasuryVault
 * @dev Secure multi-signature treasury contract for managing organization funds
 * @notice This contract implements enterprise-grade security patterns for treasury management
 */
contract TreasuryVault is Pausable, AccessControl {
    
    // ============ CUSTOM REENTRANCY GUARD ============
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    
    modifier nonReentrant() {
        require(_status != _ENTERED, "TreasuryVault: Reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    // ============ CONSTANTS ============
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TREASURY_MANAGER_ROLE = keccak256("TREASURY_MANAGER_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    
    uint256 public constant MIN_CONFIRMATION_COUNT = 2;
    uint256 public constant PROPOSAL_EXPIRY_BLOCKS = 50400; // ~7 days at 12 sec blocks
    uint256 public constant MAX_DAILY_WITHDRAWAL = 100 ether;

    // ============ STATE VARIABLES ============
    uint256 public proposalCount;
    uint256 public requiredConfirmations;
    uint256 public dailyWithdrawalLimit;
    uint256 public lastWithdrawalResetBlock;
    uint256 public todayWithdrawn;
    
    mapping(uint256 => Proposal) public proposals;
    mapping(address => bool) public isTreasuryManager;
    mapping(address => uint256) public managerIndex; // Track position in array
    address[] public treasuryManagers;

    // ============ STRUCTS ============
    struct Proposal {
        uint256 id;
        address proposer;
        address target;
        uint256 value;
        bytes data;
        string description;
        uint256 confirmations;
        uint256 deadline;
        bool executed;
        bool cancelled;
        mapping(address => bool) hasConfirmed;
    }

    // ============ EVENTS ============
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address indexed target,
        uint256 value,
        string description
    );

    event ProposalConfirmed(
        uint256 indexed proposalId,
        address indexed confirmer,
        uint256 confirmations
    );

    event ProposalExecuted(
        uint256 indexed proposalId,
        address indexed executor,
        bool success
    );

    event ProposalCancelled(uint256 indexed proposalId, address indexed canceller);

    event FundsDeposited(address indexed from, uint256 amount);
    
    event EmergencyWithdrawal(
        address indexed to,
        uint256 amount,
        address indexed authorizer
    );

    event TreasuryManagerAdded(address indexed manager, address indexed addedBy);
    event TreasuryManagerRemoved(address indexed manager, address indexed removedBy);

    event DailyLimitUpdated(uint256 oldLimit, uint256 newLimit);
    event RequiredConfirmationsUpdated(uint256 oldCount, uint256 newCount);

    // ============ MODIFIERS ============
    modifier onlyTreasuryManager() {
        require(
            hasRole(TREASURY_MANAGER_ROLE, msg.sender),
            "TreasuryVault: Caller is not a treasury manager"
        );
        _;
    }

    modifier onlyProposer() {
        require(
            hasRole(PROPOSER_ROLE, msg.sender) || hasRole(TREASURY_MANAGER_ROLE, msg.sender),
            "TreasuryVault: Caller cannot create proposals"
        );
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        require(proposalId < proposalCount, "TreasuryVault: Proposal does not exist");
        _;
    }

    modifier proposalNotExecuted(uint256 proposalId) {
        require(!proposals[proposalId].executed, "TreasuryVault: Proposal already executed");
        _;
    }

    modifier proposalNotExpired(uint256 proposalId) {
        require(
            block.number <= proposals[proposalId].deadline,
            "TreasuryVault: Proposal has expired"
        );
        _;
    }

    modifier validAddress(address _address) {
        require(_address != address(0), "TreasuryVault: Invalid address");
        _;
    }

    // ============ CONSTRUCTOR ============
    constructor(
        address[] memory _initialManagers,
        uint256 _requiredConfirmations,
        uint256 _dailyWithdrawalLimit
    ) {
        require(_initialManagers.length >= MIN_CONFIRMATION_COUNT, "TreasuryVault: Need minimum managers");
        require(
            _requiredConfirmations >= MIN_CONFIRMATION_COUNT && 
            _requiredConfirmations <= _initialManagers.length,
            "TreasuryVault: Invalid confirmation count"
        );
        require(_dailyWithdrawalLimit <= MAX_DAILY_WITHDRAWAL, "TreasuryVault: Daily limit too high");

        // Initialize reentrancy guard
        _status = _NOT_ENTERED;
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        
        // Add initial treasury managers
        for (uint256 i = 0; i < _initialManagers.length; i++) {
            require(_initialManagers[i] != address(0), "TreasuryVault: Invalid manager address");
            _grantRole(TREASURY_MANAGER_ROLE, _initialManagers[i]);
            _grantRole(PROPOSER_ROLE, _initialManagers[i]);
            isTreasuryManager[_initialManagers[i]] = true;
            managerIndex[_initialManagers[i]] = treasuryManagers.length;
            treasuryManagers.push(_initialManagers[i]);
        }

        requiredConfirmations = _requiredConfirmations;
        dailyWithdrawalLimit = _dailyWithdrawalLimit;
        lastWithdrawalResetBlock = block.number;
    }

    // ============ EXTERNAL FUNCTIONS ============

    /**
     * @dev Receive function to accept ETH deposits
     */
    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }

    /**
     * @dev Create a new proposal for fund withdrawal or contract interaction
     */
    function createProposal(
        address target,
        uint256 value,
        bytes calldata data,
        string calldata description
    )
        external
        onlyProposer
        validAddress(target)
        whenNotPaused
        returns (uint256)
    {
        require(value <= address(this).balance, "TreasuryVault: Insufficient contract balance");
        require(bytes(description).length > 0, "TreasuryVault: Description required");

        uint256 proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];
        
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.target = target;
        proposal.value = value;
        proposal.data = data;
        proposal.description = description;
        proposal.deadline = block.number + PROPOSAL_EXPIRY_BLOCKS;
        proposal.confirmations = 0;
        proposal.executed = false;
        proposal.cancelled = false;

        emit ProposalCreated(proposalId, msg.sender, target, value, description);
        return proposalId;
    }

    /**
     * @dev Confirm a proposal (multi-sig functionality)
     */
    function confirmProposal(uint256 proposalId)
        external
        onlyTreasuryManager
        proposalExists(proposalId)
        proposalNotExecuted(proposalId)
        proposalNotExpired(proposalId)
        whenNotPaused
    {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.cancelled, "TreasuryVault: Proposal is cancelled");
        require(!proposal.hasConfirmed[msg.sender], "TreasuryVault: Already confirmed");

        proposal.hasConfirmed[msg.sender] = true;
        proposal.confirmations++;

        emit ProposalConfirmed(proposalId, msg.sender, proposal.confirmations);

        // Auto-execute if enough confirmations
        if (proposal.confirmations >= requiredConfirmations) {
            _executeProposal(proposalId);
        }
    }

    /**
     * @dev Execute a confirmed proposal
     */
    function executeProposal(uint256 proposalId)
        external
        onlyTreasuryManager
        proposalExists(proposalId)
        proposalNotExecuted(proposalId)
        proposalNotExpired(proposalId)
        whenNotPaused
    {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.cancelled, "TreasuryVault: Proposal is cancelled");
        require(
            proposal.confirmations >= requiredConfirmations,
            "TreasuryVault: Not enough confirmations"
        );

        _executeProposal(proposalId);
    }

    /**
     * @dev Cancel a proposal (emergency function)
     */
    function cancelProposal(uint256 proposalId)
        external
        onlyRole(ADMIN_ROLE)
        proposalExists(proposalId)
        proposalNotExecuted(proposalId)
    {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.cancelled, "TreasuryVault: Already cancelled");
        
        proposal.cancelled = true;
        emit ProposalCancelled(proposalId, msg.sender);
    }

    /**
     * @dev Emergency withdrawal function (requires admin role)
     */
    function emergencyWithdraw(address payable to, uint256 amount)
        external
        onlyRole(ADMIN_ROLE)
        validAddress(to)
        nonReentrant
    {
        require(amount <= address(this).balance, "TreasuryVault: Insufficient balance");
        require(amount > 0, "TreasuryVault: Amount must be positive");
        require(isTreasuryManager[to] || hasRole(ADMIN_ROLE, to), "TreasuryVault: Invalid recipient");

        (bool success, ) = to.call{value: amount}("");
        require(success, "TreasuryVault: Transfer failed");
        emit EmergencyWithdrawal(to, amount, msg.sender);
    }

    /**
     * @dev Add a new treasury manager
     */
    function addTreasuryManager(address manager)
        external
        onlyRole(ADMIN_ROLE)
        validAddress(manager)
    {
        require(!isTreasuryManager[manager], "TreasuryVault: Already a manager");
        
        _grantRole(TREASURY_MANAGER_ROLE, manager);
        _grantRole(PROPOSER_ROLE, manager);
        isTreasuryManager[manager] = true;
        managerIndex[manager] = treasuryManagers.length;
        treasuryManagers.push(manager);

        emit TreasuryManagerAdded(manager, msg.sender);
    }

    /**
     * @dev Remove a treasury manager
     */
    function removeTreasuryManager(address manager)
        external
        onlyRole(ADMIN_ROLE)
        validAddress(manager)
    {
        require(isTreasuryManager[manager], "TreasuryVault: Not a manager");
        require(treasuryManagers.length > MIN_CONFIRMATION_COUNT, "TreasuryVault: Cannot remove last managers");
        
        _revokeRole(TREASURY_MANAGER_ROLE, manager);
        _revokeRole(PROPOSER_ROLE, manager);
        isTreasuryManager[manager] = false;

        // Remove from array using efficient O(1) removal
        uint256 index = managerIndex[manager];
        uint256 lastIndex = treasuryManagers.length - 1;
        
        if (index != lastIndex) {
            address lastManager = treasuryManagers[lastIndex];
            treasuryManagers[index] = lastManager;
            managerIndex[lastManager] = index;
        }
        
        treasuryManagers.pop();
        delete managerIndex[manager];

        emit TreasuryManagerRemoved(manager, msg.sender);
    }

    /**
     * @dev Update required confirmations count
     */
    function updateRequiredConfirmations(uint256 newCount)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(
            newCount >= MIN_CONFIRMATION_COUNT && newCount <= treasuryManagers.length,
            "TreasuryVault: Invalid confirmation count"
        );
        
        uint256 oldCount = requiredConfirmations;
        requiredConfirmations = newCount;
        
        emit RequiredConfirmationsUpdated(oldCount, newCount);
    }

    /**
     * @dev Update daily withdrawal limit
     */
    function updateDailyLimit(uint256 newLimit)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(newLimit <= MAX_DAILY_WITHDRAWAL, "TreasuryVault: Limit too high");
        
        uint256 oldLimit = dailyWithdrawalLimit;
        dailyWithdrawalLimit = newLimit;
        
        emit DailyLimitUpdated(oldLimit, newLimit);
    }

    /**
     * @dev Emergency pause function
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause function
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ============ PUBLIC VIEW FUNCTIONS ============

    /**
     * @dev Get contract balance
     */
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Get proposal details
     */
    function getProposal(uint256 proposalId)
        public
        view
        proposalExists(proposalId)
        returns (
            uint256 id,
            address proposer,
            address target,
            uint256 value,
            bytes memory data,
            string memory description,
            uint256 confirmations,
            uint256 deadline,
            bool executed,
            bool cancelled
        )
    {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.id,
            proposal.proposer,
            proposal.target,
            proposal.value,
            proposal.data,
            proposal.description,
            proposal.confirmations,
            proposal.deadline,
            proposal.executed,
            proposal.cancelled
        );
    }

    /**
     * @dev Check if address has confirmed a proposal
     */
    function hasConfirmed(uint256 proposalId, address manager)
        public
        view
        proposalExists(proposalId)
        returns (bool)
    {
        return proposals[proposalId].hasConfirmed[manager];
    }

    /**
     * @dev Get all treasury managers
     */
    function getTreasuryManagers() public view returns (address[] memory) {
        return treasuryManagers;
    }

    /**
     * @dev Get remaining daily withdrawal amount
     */
    function getRemainingDailyWithdrawal() public view returns (uint256) {
        if (block.number >= lastWithdrawalResetBlock + 7200) {
            return dailyWithdrawalLimit;
        }
        return dailyWithdrawalLimit - todayWithdrawn;
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @dev Internal function to execute proposal
     */
    function _executeProposal(uint256 proposalId) internal nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;

        // Check daily withdrawal limit for ETH transfers
        if (proposal.value > 0) {
            _checkDailyLimit(proposal.value);
        }

        // Execute the transaction
        (bool success, ) = proposal.target.call{value: proposal.value}(proposal.data);
        
        // FIXED: Use require instead of reverting state after external call
        require(success, "TreasuryVault: Proposal execution failed");
        
        emit ProposalExecuted(proposalId, msg.sender, success);
    }

    /**
     * @dev Check and update daily withdrawal limit
     */
    function _checkDailyLimit(uint256 amount) internal {
        // Reset daily counter if 24 hours have passed
        if (block.number >= lastWithdrawalResetBlock + 7200) {
            lastWithdrawalResetBlock = block.number;
            todayWithdrawn = 0;
        }

        require(
            todayWithdrawn + amount <= dailyWithdrawalLimit,
            "TreasuryVault: Daily withdrawal limit exceeded"
        );
        
        todayWithdrawn += amount;
    }
}
