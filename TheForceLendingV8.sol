/**
 *Submitted for verification at Etherscan.io on 2019-09-17
*/
pragma solidity ^0.4.24;

contract SafeMath {
  function safeMul(uint a, uint b) pure internal returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function safeSub(uint a, uint b) pure internal returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function safeAdd(uint a, uint b) pure internal returns (uint) {
    uint c = a + b;
    assert(c>=a && c>=b);
    return c;
  }

}

contract EIP20Interface {
    /* This is a slight change to the ERC20 base standard.
    function totalSupply() constant returns (uint256 supply);
    is replaced with:
    uint256 public totalSupply;
    This automatically creates a getter function for the totalSupply.
    This is moved to the base contract since public getter functions are not
    currently recognised as an implementation of the matching abstract
    function by the compiler.
    */
    /// total amount of tokens
    uint256 public totalSupply;

    /// @param _owner The address from which the balance will be retrieved
    /// @return The balance
    function balanceOf(address _owner) public view returns (uint256 balance);

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) public returns (bool success);

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);

    /// @notice `msg.sender` approves `_spender` to spend `_value` tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of tokens to be approved for transfer
    /// @return Whether the approval was successful or not
    function approve(address _spender, uint256 _value) public returns (bool success);

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) public view returns (uint256 remaining);

    // solhint-disable-next-line no-simple-event-func-name
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}

contract ErrorReporter {

    /**
      * @dev `error` corresponds to enum Error; `info` corresponds to enum FailureInfo, and `detail` is an arbitrary
      * contract-specific code that enables us to report opaque error codes from upgradeable contracts.
      **/
    event Failure(string name, uint error);

    enum Error {
        NO_ERROR,
        INVALIDE_ADMIN,
        WITHDRAW_TOKEN_AMOUNT_ERROR,
        WITHDRAW_TOKEN_TRANSER_ERROR,
        TOKEN_INSUFFICIENT_ALLOWANCE,
        TOKEN_INSUFFICIENT_BALANCE,
        TRANSFER_FROM_ERROR,
        LENDER_INSUFFICIENT_BORROW_ALLOWANCE,
        LENDER_INSUFFICIENT_BORROWER_BALANCE,
        LENDER_TRANSFER_FROM_BORROW_ERROR,
        LENDER_INSUFFICIENT_ADMIN_ALLOWANCE,
        LENDER_INSUFFICIENT_ADMIN_BALANCE,
        LENDER_TRANSFER_FROM_ADMIN_ERROR,
        CALL_MARGIN_ALLOWANCE_ERROR,
        CALL_MARGIN_BALANCE_ERROR,
        CALL_MARGIN_TRANSFER_ERROR,
        REPAY_ALLOWANCE_ERROR,
        REPAY_BALANCE_ERROR,
        REPAY_TX_ERROR,
        FORCE_REPAY_ALLOWANCE_ERROR,
        FORCE_REPAY_BALANCE_ERROR,
        FORCE_REPAY_TX_ERROR,
        CLOSE_POSITION_ALLOWANCE_ERROR,
        CLOSE_POSITION_TX_ERROR,
        CLOSE_POSITION_MUST_ADMIN_BEFORE_DEADLINE,
        CLOSE_POSITION_MUST_ADMIN_OR_LENDER_AFTER_DEADLINE,
        LENDER_TEST_TRANSFER_ADMIN_ERROR,
        LENDER_TEST_TRANSFER_BORROWR_ERROR,
        LENDER_TEST_TRANSFERFROM_ADMIN_ERROR,
        LENDER_TEST_TRANSFERFROM_BORROWR_ERROR,
        SEND_TOKEN_AMOUNT_ERROR,
        SEND_TOKEN_TRANSER_ERROR,
        DEPOSIT_TOKEN,
        CANCEL_ORDER,
        REPAY_ERROR,
        FORCE_REPAY_ERROR,
        LENDER_SEND_ETH_ERROR,
        REPAY_SEND_ETH_ERROR,
        FORCE_REPAY_SEND_ETH_ERROR
    }

    /**
      * @dev use this when reporting a known error from the money market or a non-upgradeable collaborator
      */
    function fail(string name, Error err) internal returns (uint) {
        emit Failure(name, uint(err));

        return uint(err);
    }
}

library ERC20AsmFn {

    function isContract(address addr) internal {
        assembly {
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }
    }

